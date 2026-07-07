# Collectors convention: every function below derives a Tables.jl row table purely from
# data the hot loop already writes for free (`B.history`, `B.equity_history`, `B.market`'s
# retained price matrices). No per-bar hot-path cost, no caching — add new collectors the
# same way rather than tracking a new series eagerly in `process_all!`.
#
# When the market has a time axis, every bar-keyed table gains a trailing
# `timestamp::DateTime` column; without one, row types are unchanged.

_with_timestamps(rows, axis::Union{Nothing,Vector{DateTime}}) =
  axis === nothing ? rows : [merge(r, (timestamp=axis[r.bar],)) for r in rows]

# Historical base-conversion rate for A at `bar`: last non-NaN Close of A's fx asset at or
# before that bar (1.0 when the asset is base-denominated). Cold path only.
function _fx_rate_at(A::Asset, bar::Int)
  f = A.fx
  f === nothing && return 1.0
  col = min(bar, size(f.data, 2))
  row = f.close_idx > 0 ? f.close_idx : f._idx["Close"]
  while col > 0 && isnan(f.data[row, col])
    col -= 1
  end
  return col == 0 ? NaN : f.data[row, col]
end

const TradeRow = @NamedTuple{bar::Int, ticker::String, kind::Symbol,
  strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing},
  volume::Float64, price::Float64, delta_cash::Float64}

# `price(T)` reprices in the asset's local currency; the table reports base currency
# (consistent with `delta_cash`) using the rate at the trade's bar.
function _trade_row(T::Trade)
  key = instrument_key(T.derivative)
  rate = _fx_rate_at(T.derivative.underlying, T.date)
  return TradeRow((T.date, key.ticker, key.kind, key.strike, key.expiry,
    T.volume, Float64(price(T)) * rate, T.delta_cash))
end

"""
    trades_table(B::Broker)

Every fill in `B.history` as a Tables.jl row table.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
advance_to!(B.market, 1);
A=B.market.assets[2];
place_order!(B, Order(Buy(A,10)));
process_all!(B);
length(trades_table(B))
# output

1
```
"""
trades_table(B::Broker) =
  _with_timestamps(TradeRow[_trade_row(T) for T in B.history], B.market.axis)

const PositionRow = @NamedTuple{ticker::String, kind::Symbol,
  strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing},
  net_qty::Float64, avg_cost::Float64, realized_pnl::Float64}

_position_row((key, P)) = PositionRow((key.ticker, key.kind, key.strike, key.expiry,
  P.net_qty, P.avg_cost, P.realized_pnl))

"""
    positions_table(B::Broker)

Every open position in `B.portfolio` as a Tables.jl row table.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
advance_to!(B.market, 1);
A=B.market.assets[2];
place_order!(B, Order(Buy(A,10)));
process_all!(B);
length(positions_table(B))
# output

1
```
"""
positions_table(B::Broker) =
  PositionRow[_position_row(kp) for kp in zip(keys(B.portfolio), values(B.portfolio))]

const EquityRow = @NamedTuple{bar::Int, equity::Float64}

"""
    equity_table(B::Broker)

The equity curve (`B.equity_history`) as a Tables.jl row table.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
advance_to!(B.market, 1);
process_all!(B);
length(equity_table(B))
# output

1
```
"""
equity_table(B::Broker) = _with_timestamps(
  EquityRow[(bar=i, equity=e) for (i, e) in enumerate(B.equity_history)], B.market.axis
)

const CashflowRow = @NamedTuple{bar::Int, cash::Float64}

"""
    cashflows_table(B::Broker)

The cash balance over time (`cash_history`) as a Tables.jl row table.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
advance_to!(B.market, 1);
A=B.market.assets[2];
place_order!(B, Order(Buy(A,10)));
process_all!(B);
length(cashflows_table(B))
# output

3
```
"""
cashflows_table(B::Broker) = _with_timestamps(
  CashflowRow[(bar=d, cash=Float64(c)) for (d, c) in cash_history(B)], B.market.axis
)

const TurnoverRow = @NamedTuple{bar::Int, traded_notional::Float64, turnover::Float64}

"""
    turnover_table(B::Broker)

Per-bar traded notional and turnover (`traded_notional / equity`) as a Tables.jl row table.
Uses `delta_cash` rather than `volume`/`price(T)`: close-out trades from
[`resolve_portfolio!`](@ref) are recorded with `volume == 0.0` (the cash impact is carried
by `delta_cash` instead), so `volume`-based notional would silently drop every forced close.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
advance_to!(B.market, 1);
A=B.market.assets[2];
place_order!(B, Order(Buy(A,10)));
process_all!(B);
length(turnover_table(B))
# output

1
```
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
  return _with_timestamps(out, B.market.axis)
end

const WeightRow = @NamedTuple{
  bar::Int, ticker::String, kind::Symbol, value::Float64, weight::Float64
}

"""
    weights_table(B::Broker)

Per-bar, per-instrument notional value and weight-of-equity as a Tables.jl row table.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
advance_to!(B.market, 1);
A=B.market.assets[2];
place_order!(B, Order(Buy(A,10)));
process_all!(B);
length(weights_table(B))
# output

1
```
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
      rate = _fx_rate_at(A, bar)      # base-currency mark, consistent with equity
      isnan(rate) && continue
      val = q * payoff(deriv[key], p) * rate
      w = eq == 0.0 ? 0.0 : val / eq
      push!(out, WeightRow((bar, key.ticker, key.kind, val, w)))
    end
  end
  return _with_timestamps(out, B.market.axis)
end
