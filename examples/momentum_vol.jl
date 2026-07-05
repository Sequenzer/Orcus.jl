using Orcus
using Plots
unicodeplots()
using Statistics

# ── Market ────────────────────────────────────────────────────────────────────
# 10-stock diversified universe, last 5 000 bars (~20 years of dense data)
let tickers = ["KO", "MO", "DIS", "MRO", "HAL", "BA", "GE", "HON", "AXP", "USB"]
  raw = load_stocks(tickers)
  global M = trim_to_length(raw, 5_000)
end

# ── Strategy ──────────────────────────────────────────────────────────────────
#
# Cross-Sectional Momentum + Volatility Targeting
# ------------------------------------------------
# Signal: 12-1 month momentum = log(S[n-21] / S[n-252])
#   Skipping the last month avoids the well-documented short-term reversal
#   effect (Jegadeesh & Titman 1993; Asness et al. 2013).
#
# Filter: only buy stocks trading above their 200-bar EMA. This removes
#   falling-knife scenarios and concentrates exposure in uptrending names.
#
# Sizing: volatility-target each leg so the strategy maintains ~15%
#   annualised portfolio volatility regardless of market regime.
#   qty = floor((base_notional * clamp(target_vol / vol_20d, 0.5, 2)) / price)
#
# Portfolio: long top n_legs stocks by momentum score (among eligible).
#   Remaining cash stays uninvested when fewer than n_legs pass the filter.
#
# Rebalance: every 21 bars (≈ one calendar month).

mutable struct MomentumVol <: Strategy
  broker::Broker
  market::Market
  nms::Vector{String}
  last_rebal::Int
  rebal_every::Int       # bars between rebalances (21)
  mom_w::Int             # momentum lookback (252)
  skip_w::Int            # short-term skip (21)
  ema_w::Int             # EMA trend filter window (200)
  vol_w::Int             # volatility estimation window (20)
  n_legs::Int            # max long positions (3)
  target_vol_d::Float64  # daily vol target = 0.15/√252
  base_notional::Float64 # $ per leg before vol scaling

  function MomentumVol(b::Broker)
    nms = asset_names(b.market)
    new(b, b.market, nms,
      0, 21, 252, 21, 200, 20, 3,
      0.15 / sqrt(252), 5_000.0)
  end
end

@strategy_methods MomentumVol mom_vol_next mom_vol_init

function mom_vol_init(s::MomentumVol) end

function mom_vol_next(s::MomentumVol)
  n = length(s.market)
  # Need at least mom_w + skip_w + ema_w bars
  n < s.mom_w + s.ema_w && return nothing
  n - s.last_rebal < s.rebal_every && return nothing
  s.last_rebal = n

  request_to_close_all!(s.broker)

  scores = Float64[]
  eligible = String[]
  qtys = Dict{String,Int}()

  for nm in s.nms
    a = s.market.data[nm]
    # Filter to trading days only (aligned series includes weekends/holidays as NaN)
    close = filter(!isnan, Float64.(a["Close"]))
    nc = length(close)
    nc < s.mom_w + 1 && continue

    # 12-1 month momentum (log return from 252 trading days ago to 21 days ago)
    p_now = close[nc - s.skip_w]
    p_old = close[nc - s.mom_w]
    (p_old <= 0 || p_now <= 0) && continue
    score = log(p_now / p_old)
    (isnan(score) || isinf(score)) && continue

    # EMA trend filter: current close must be above EMA(200)
    ema_vec = ema(close, s.ema_w)
    ema_now = ema_vec[nc]
    isnan(ema_now) && continue
    close[nc] <= ema_now && continue   # below trend — skip

    # 20-day realised vol for sizing
    vol_rets = diff(log.(close[(nc - s.vol_w):nc]))
    vol_20d = std(vol_rets)
    price = close[nc]
    price <= 0 && continue

    scale = vol_20d < 1e-10 ? 1.0 : clamp(s.target_vol_d / vol_20d, 0.5, 2.0)
    qty = max(1, floor(Int, s.base_notional * scale / price))

    push!(scores, score)
    push!(eligible, nm)
    qtys[nm] = qty
  end

  isempty(eligible) && return nothing

  # Long top n_legs by momentum score
  order = sortperm(scores; rev=true)
  picked = eligible[order[1:min(s.n_legs, length(order))]]

  for nm in picked
    a = s.market.data[nm]
    place_order!(s.broker, Order(Buy(a), qtys[nm]))
  end
end

# ── Run ───────────────────────────────────────────────────────────────────────
bt = Backtest(M, MomentumVol, 50_000)
run_test(bt)

# ── Results ───────────────────────────────────────────────────────────────────
bah = bah_equity(bt.market, 50_000)
extended_summary(bt; benchmark=bah)

println("\n=== Strategy vs Equal-Weight Buy-and-Hold ===")
compare_backtests(
  [bt],
  ["MomentumVol"];
  benchmark=bah,
)

println("\n=== Equity Curve ===")
display(plot(bt))
