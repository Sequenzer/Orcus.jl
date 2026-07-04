# Collectors convention: every function below derives a Tables.jl row table purely from
# data the hot loop already writes for free (`B.history`, `B.equity_history`, `B.market`'s
# retained price matrices). No per-bar hot-path cost, no caching — add new collectors the
# same way rather than tracking a new series eagerly in `process_all!`.

export
  trades_table,
  positions_table,
  equity_table,
  cashflows_table,
  turnover_table,
  weights_table

const TradeRow = @NamedTuple{bar::Int, ticker::String, kind::Symbol,
  strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing},
  volume::Float64, price::Float64, delta_cash::Float64}

function _trade_row(T::Trade)
  key = instrument_key(T.derivative)
  return TradeRow((T.date, key.ticker, key.kind, key.strike, key.expiry,
    T.volume, Float64(price(T)), T.delta_cash))
end

"""
    trades_table(B::Broker)

Every fill in `B.history` as a Tables.jl row table.
"""
trades_table(B::Broker) = TradeRow[_trade_row(T) for T in B.history]

const PositionRow = @NamedTuple{ticker::String, kind::Symbol,
  strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing},
  net_qty::Float64, avg_cost::Float64, realized_pnl::Float64}

_position_row((key, P)) = PositionRow((key.ticker, key.kind, key.strike, key.expiry,
  P.net_qty, P.avg_cost, P.realized_pnl))

"""
    positions_table(B::Broker)

Every open position in `B.portfolio` as a Tables.jl row table.
"""
positions_table(B::Broker) =
  PositionRow[_position_row(kp) for kp in zip(keys(B.portfolio), values(B.portfolio))]

const EquityRow = @NamedTuple{bar::Int, equity::Float64}

"""
    equity_table(B::Broker)

The equity curve (`B.equity_history`) as a Tables.jl row table.
"""
equity_table(B::Broker) =
  EquityRow[(bar=i, equity=e) for (i, e) in enumerate(B.equity_history)]

const CashflowRow = @NamedTuple{bar::Int, cash::Float64}

"""
    cashflows_table(B::Broker)

The cash balance over time (`cash_history`) as a Tables.jl row table.
"""
cashflows_table(B::Broker) =
  CashflowRow[(bar=d, cash=Float64(c)) for (d, c) in cash_history(B)]

const TurnoverRow = @NamedTuple{bar::Int, traded_notional::Float64, turnover::Float64}

"""
    turnover_table(B::Broker)

Per-bar traded notional and turnover (`traded_notional / equity`) as a Tables.jl row table.
Uses `delta_cash` rather than `volume`/`price(T)`: close-out trades from
[`resolve_portfolio!`](@ref) are recorded with `volume == 0.0` (the cash impact is carried
by `delta_cash` instead), so `volume`-based notional would silently drop every forced close.
"""
function turnover_table(B::Broker)
  n = length(B.equity_history)
  n == 0 && return TurnoverRow[]
  out = TurnoverRow[]
  sizehint!(out, n)
  i = 1
  nh = length(B.history)
  for bar in 1:n
    notional = 0.0
    while i <= nh && B.history[i].date == bar
      notional += abs(B.history[i].delta_cash)
      i += 1
    end
    eq = B.equity_history[bar]
    push!(out, TurnoverRow((bar, notional, eq == 0.0 ? 0.0 : notional / eq)))
  end
  return out
end

const WeightRow = @NamedTuple{
  bar::Int, ticker::String, kind::Symbol, value::Float64, weight::Float64
}

"""
    weights_table(B::Broker)

Per-bar, per-instrument notional value and weight-of-equity as a Tables.jl row table.
Replays `B.history` forward to rebuild net quantity per instrument over time (assets retain
their full price matrix — `visible` is only a cursor — so historical marks are just an
indexed read), then marks each open lot via [`payoff`](@ref) at that bar's Close, generic
over every `Derivative` type.
"""
function weights_table(B::Broker)
  n = length(B.equity_history)
  n == 0 && return WeightRow[]
  out = WeightRow[]
  qty = Dict{InstrumentKey,Float64}()
  deriv = Dict{InstrumentKey,Derivative}()
  last_price = Dict{String,Float64}()
  i = 1
  nh = length(B.history)
  for bar in 1:n
    while i <= nh && B.history[i].date == bar
      T = B.history[i]
      key = instrument_key(T.derivative)
      if T.volume == 0.0
        qty[key] = 0.0                 # close-out sentinel: flatten, see docstring
      else
        qty[key] = get(qty, key, 0.0) + T.volume
        deriv[key] = T.derivative
      end
      i += 1
    end
    eq = B.equity_history[bar]
    for (key, q) in qty
      q == 0.0 && continue
      A = B.market.data[key.ticker]
      p = bar <= size(A.data, 2) ? A.data[A.close_idx, bar] : NaN
      if isnan(p)
        p = get(last_price, key.ticker, NaN)
      else
        last_price[key.ticker] = p
      end
      isnan(p) && continue            # no valid mark observed yet for this ticker
      val = q * payoff(deriv[key], p)
      w = eq == 0.0 ? 0.0 : val / eq
      push!(out, WeightRow((bar, key.ticker, key.kind, val, w)))
    end
  end
  return out
end
