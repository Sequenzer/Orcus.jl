using Orcus
using Plots
unicodeplots()
using Statistics

# ── Market ────────────────────────────────────────────────────────────────────
# KO and MO: stable consumer staples with long histories, realistic for
# systematic put-selling (low beta, reliable dividends, liquid options markets).
let tickers = ["KO", "MO"]
  raw = load_stocks(tickers)
  global M = trim_to_length(raw, 3_000)
end

# ── Strategy ──────────────────────────────────────────────────────────────────
#
# Option Wheel (Cash-Secured Put → Covered Call)
# -----------------------------------------------
# Phase 1 — SHORT PUT:
#   Every 21 bars, sell a 5%-OTM cash-secured put.
#   Premium set by Black-Scholes-Merton using 60-bar realized vol as IV proxy.
#   If S_T < K at expiry (assigned): buy stock, transition to covered-call phase.
#   If S_T ≥ K (expired OTM): keep premium, sell new put.
#
# Phase 2 — COVERED CALL:
#   Hold long stock and sell a 5%-OTM covered call each 21-bar cycle.
#   If S_T > K_call (called away): sell stock at effective K, return to put phase.
#   If S_T ≤ K_call: keep stock, sell new covered call.
#
# Framework note: Orcus options are priced at intrinsic value between cycles
# (no theta decay mid-period). Terminal payoff at each 21-bar expiry is
# economically exact. BSM is used only for the initial premium at open.
#
# Cash flow accounting (Orcus sign conventions):
#   Short put open:  cash += premium  (price(ShortPut) = −premium → cash −= −premium)
#   Short put close: cash −= max(K−S_T, 0)  (assignment loss)
#   Buy stock open:  cash −= qty × S
#   Short call open: cash += cc_premium
#   Short call close: cash −= max(S_T−K_call, 0)  (call exercised against us)

mutable struct OptionWheel <: Strategy
  broker::Broker
  market::Market
  nms::Vector{String}
  phase::Dict{String,Symbol}         # :put_selling or :covered_call
  expiry_bar::Dict{String,Int}       # bar when current contract expires
  put_strike::Dict{String,Float64}   # K for open short put
  call_strike::Dict{String,Float64}  # K for open covered call
  qty::Dict{String,Int}              # shares per contract per ticker
  cycle::Int                         # bars per expiry cycle
  vol_w::Int                         # bars for realized vol estimate
  r::Float64                         # annualized risk-free rate
  notional::Float64                  # target $ per leg

  function OptionWheel(b::Broker)
    nms = asset_names(b.market)
    new(b, b.market, nms,
      Dict(nm => :put_selling for nm in nms),
      Dict(nm => 0 for nm in nms),
      Dict(nm => 0.0 for nm in nms),
      Dict(nm => 0.0 for nm in nms),
      Dict(nm => 0 for nm in nms),
      21, 60, 0.04, 5_000.0)
  end
end

@strategy_methods OptionWheel wheel_next wheel_init

function wheel_init(s::OptionWheel) end

function wheel_next(s::OptionWheel)
  n = length(s.market)
  # Need at least vol_w trading days ≈ vol_w * 7/5 calendar bars
  n < round(Int, s.vol_w * 1.5) && return nothing

  T_years = s.cycle / 252   # time to expiry in years

  for nm in s.nms
    a = s.market.data[nm]
    # Filter to trading days only (aligned series includes weekends/holidays as NaN)
    close = filter(x -> !isnan(x) && x > 0, Float64.(a["Close"]))
    nc = length(close)
    nc < s.vol_w + 1 && continue

    S = close[nc]
    rv = realized_vol(close, s.vol_w)
    isnan(rv) && continue

    # ── First bar: open initial put ────────────────────────────────────
    if s.expiry_bar[nm] == 0
      qty = max(1, floor(Int, s.notional / S))
      s.qty[nm] = qty
      K = 0.95 * S
      prem = bsm_put(S, K, T_years, s.r, rv)
      s.put_strike[nm] = K
      s.expiry_bar[nm] = n + s.cycle
      place_order!(s.broker, Order(ShortPut(a, K, prem), qty))
      continue
    end

    # ── Not yet at expiry ──────────────────────────────────────────────
    n < s.expiry_bar[nm] && continue

    # ── Expiry: close all open positions for this ticker ───────────────
    request_to_close!(s.broker, nm)
    s.expiry_bar[nm] = n + s.cycle
    qty = s.qty[nm]

    if s.phase[nm] == :put_selling
      K = s.put_strike[nm]
      if S < K
        # Assigned: buy stock, sell covered call
        s.phase[nm] = :covered_call
        K_call = 1.05 * S
        s.call_strike[nm] = K_call
        cc_prem = bsm_call(S, K_call, T_years, s.r, rv)
        place_order!(s.broker, Order(Buy(a), qty))
        place_order!(s.broker, Order(ShortCall(a, K_call, cc_prem), qty))
      else
        # Expired OTM: sell new put
        K_new = 0.95 * S
        s.put_strike[nm] = K_new
        prem = bsm_put(S, K_new, T_years, s.r, rv)
        place_order!(s.broker, Order(ShortPut(a, K_new, prem), qty))
      end

    else  # :covered_call
      K_call = s.call_strike[nm]
      if S > K_call
        # Called away: stock sold effectively at K_call, return to put phase
        s.phase[nm] = :put_selling
        K_new = 0.95 * S
        s.put_strike[nm] = K_new
        prem = bsm_put(S, K_new, T_years, s.r, rv)
        place_order!(s.broker, Order(ShortPut(a, K_new, prem), qty))
      else
        # Not called: keep stock, sell new covered call
        K_new = 1.05 * S
        s.call_strike[nm] = K_new
        cc_prem = bsm_call(S, K_new, T_years, s.r, rv)
        place_order!(s.broker, Order(Buy(a), qty))
        place_order!(s.broker, Order(ShortCall(a, K_new, cc_prem), qty))
      end
    end
  end
end

# ── Run ───────────────────────────────────────────────────────────────────────
bt = Backtest(M, OptionWheel, 20_000)
run_test(bt)

# ── Results ───────────────────────────────────────────────────────────────────
bah = bah_equity(bt.market, 20_000)
extended_summary(bt; benchmark=bah)

println("\n=== Strategy vs Equal-Weight Buy-and-Hold ===")
compare_backtests(
  [bt],
  ["OptionWheel"];
  benchmark=bah,
)

println("\n=== Equity Curve ===")
display(plot(bt))
