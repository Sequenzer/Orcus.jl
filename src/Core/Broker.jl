
"""

    Broker(market::Market, cash::Real; cost_model::CostModel=NoCost(), margin_model::MarginModel=NoMargin())

The order-executing unit of the system. Holds cash, a `Market`, a pluggable transaction
`cost_model`, a pluggable `margin_model`, a netted `portfolio` (keyed by `instrument_key`),
the open `orders` queue (FIFO), the executed-trade `history`, a list of `rejected` orders,
a list of `margin_calls` (bar indices where a maintenance breach forced a full liquidation),
and the `equity_history`.

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=Market([x,y]);
B = Broker(M,1000);
isa(B,Broker)
# output

true
```
"""
mutable struct Broker
  cash::Float64
  market::Market
  cost_model::CostModel
  margin_model::MarginModel                      # pluggable leverage/liquidation model
  portfolio::Portfolio                           # positions grouped by concrete derivative type
  orders::Vector{Order}                          # FIFO queue
  history::Vector{Trade}
  rejected::Vector{Tuple{Order,String,Int}}      # (order, reason, bar)
  margin_calls::Vector{Int}                      # bar indices where a maintenance breach forced a liquidation
  equity_history::Vector{Float64}
  _pending_close::Bool                           # set when a close is requested; lets resolve_portfolio! skip the per-bar scan
  function Broker(
    market::Market, cash::Real; cost_model::CostModel=NoCost(),
    margin_model::MarginModel=NoMargin(),
  )
    this = new()
    this.cash = Float64(cash)
    this.market = market
    this.cost_model = cost_model
    this.margin_model = margin_model
    this.portfolio = Portfolio()
    this.orders = Vector{Order}()
    this.history = Vector{Trade}()
    this.rejected = Tuple{Order,String,Int}[]
    this.margin_calls = Int[]
    this.equity_history = Float64[]
    this._pending_close = false
    return this
  end
end

"""
    broker(market::Market, cash::Real; cost_model::CostModel=NoCost(), margin_model::MarginModel=NoMargin())
    broker(n_Assets::Int, cash::Real; cost_model::CostModel=NoCost(), margin_model::MarginModel=NoMargin())

Build a `Broker`. With a `market`, wraps it directly. With an asset count, builds a market of
that many random assets first.

```jldoctest
Random.seed!(1);
B = broker(3, 1000);
length(B.market.assets)
# output

3
```
"""
broker(
  market::Market,
  cash::Real;
  cost_model::CostModel=NoCost(),
  margin_model::MarginModel=NoMargin(),
) =
  Broker(market, cash; cost_model=cost_model, margin_model=margin_model)

function broker(
  n_Assets::Int,
  cash::Real;
  cost_model::CostModel=NoCost(),
  margin_model::MarginModel=NoMargin(),
)
  M = market()
  foreach(x -> add_asset!(M, asset()), 1:n_Assets)
  return Broker(M, cash; cost_model=cost_model, margin_model=margin_model)
end

Base.show(io::IO, B::Broker) = print(
  io, "Broker with $(round(B.cash;digits=2)) funds and $(length(B.orders)) open orders"
)

"""

    place_order!(B::Broker,O::Order)

Place an Order in the Broker's Orderbook

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.assets[2]
O = Order(Buy(A,10))
place_order!(B,O)
B
# output

Broker with 1000.0 funds and 1 open orders
```
"""
function place_order!(B::Broker, O::Order)
  #ToDo Check if requirements for placement are met
  push!(B.orders, O)
  return nothing
end

@inline function transaction_fee(cm::CostModel, notional::Real)
  c = transaction_cost(cm, notional)
  return c.commission + c.slippage
end

"""
    affordable_quantity(cm::CostModel, fill_price::Real, qty::Real, cash::Real; margin_pct::Real=1.0) -> Float64

Largest `|qty|`-capped signed quantity (same sign as `qty`) whose `margin_pct` fraction of
notional plus transaction cost fits within `cash`, at `fill_price` per unit. `margin_pct=1.0`
(the default) reproduces the pre-margin behavior exactly. Assumes
cost scales linearly with `|notional|`.
"""
function affordable_quantity(
  cm::CostModel, fill_price::Real, qty::Real, cash::Real; margin_pct::Real=1.0
)
  fill_price * qty <= 0.0 && return Float64(qty)   # inflow (or zero) — no cash constraint
  c = transaction_cost(cm, 1.0)
  rho = c.commission + c.slippage
  max_qty = (cash / (margin_pct + rho)) / abs(fill_price)
  return sign(qty) * min(abs(qty), max(max_qty, 0.0))
end

"""
    affordable_short_quantity(rate::Real, fill_price::Real, qty::Real, cash::Real) -> Float64

Largest `|qty|`-capped signed quantity (same sign as `qty`) whose notional times `rate`
(the resolved [`short_margin_rate`](@ref)) fits within `cash`. `rate=0.0` (the `NoMargin`
default) returns `qty` unchanged — unconstrained, matching the pre-margin behavior for shorts.
"""
function affordable_short_quantity(rate::Real, fill_price::Real, qty::Real, cash::Real)
  rate == 0.0 && return Float64(qty)
  max_qty = cash / (rate * abs(fill_price))
  return sign(qty) * min(abs(qty), max(max_qty, 0.0))
end

@inline function _reject!(B::Broker, O::Order, date::Int, strict::Bool)
  strict && error("Insufficient funds")
  push!(B.rejected, (O, "insufficient funds", date))
  return B
end

"""
    execute!(B::Broker, O::Order, date::Int=length(B); strict::Bool=false)

The single fill path used by every order-processing function. Checks whether `O` triggers on
`date` via `check_trigger` — market orders always do, limit/stop orders only when the
bar's range reaches their trigger price. On trigger, resolves how much cash this fill actually
needs:

- A same-direction **long** open/add (adding to or opening a position in the same direction as
  the fill) is margin-financeable: only `notional*initial_margin_pct(B.margin_model) + fee` is
  drawn from cash, the rest is broker-financed (`Position.loan`).
- A same-direction **short** open/add requires `abs(notional)*short_margin_rate(B.margin_model)`
  cash on hand as a pre-condition (no financing — proceeds still credit in full, as always).
- A **reducing or flipping** fill (opposite sign of the position's `net_qty`) is never
  margin-financed — full `notional+fee` required, exactly the pre-margin formula. Any
  outstanding `loan` on the position is repaid proportionally to the fraction closed.

With `B.margin_model = NoMargin()` (the default), `initial_margin_pct == 1.0` and
`short_margin_rate == 0.0` reproduce today's exact formulas for both sides.

Insufficient funds are recorded in `B.rejected`, unless `strict=true`, in which case they
error — unless `O.allow_partial` is set, in which case the affordable fraction fills instead
and the order stays open in the book for the remainder. A resting, untriggered limit/stop order
is left untouched (not fulfilled, not rejected).
"""
function execute!(
  B::Broker, O::Order{D,K}, date::Int=length(B); strict::Bool=false
) where {D<:Derivative,K<:OrderKind}
  if isfulfilled(O)
    strict && error("Order already fulfilled")
    return B
  end

  triggered, fill_price = check_trigger(O, B, date)
  if !triggered
    strict && error("Order not triggered")
    return B
  end
  # base-book boundary: everything downstream (notional, fee, avg_cost, cash, delta_cash)
  # is in the broker's base currency
  fill_price = _fx_convert(O.derivative.underlying, fill_price)

  qty = remaining(O)
  key = instrument_key(O.derivative)
  P = get_or_create!(B.portfolio, key, O.derivative)  # typed Position{D}
  P.derivative = O.derivative                           # refresh mark-to-market reference

  opening_or_adding = P.net_qty == 0.0 || sign(qty) == sign(P.net_qty)
  notional = fill_price * qty                           # signed gross
  borrowed = 0.0
  fee = 0.0

  if opening_or_adding && notional > 0.0
    # long open/add — margin-financeable
    pct = initial_margin_pct(B.margin_model)
    fee = transaction_fee(B.cost_model, notional)
    if B.cash - (notional * pct + fee) < 0
      O.allow_partial || return _reject!(B, O, date, strict)
      qty = affordable_quantity(B.cost_model, fill_price, qty, B.cash; margin_pct=pct)
      qty == 0.0 && return _reject!(B, O, date, strict)
      notional = fill_price * qty
      fee = transaction_fee(B.cost_model, notional)
    end
    borrowed = notional - notional * pct
  elseif opening_or_adding
    # short open/add (notional <= 0) — skin-in-the-game gate, no financing
    rate = short_margin_rate(B.margin_model)
    if B.cash < abs(notional) * rate
      O.allow_partial || return _reject!(B, O, date, strict)
      qty = affordable_short_quantity(rate, fill_price, qty, B.cash)
      qty == 0.0 && return _reject!(B, O, date, strict)
      notional = fill_price * qty
    end
    fee = transaction_fee(B.cost_model, notional)
  else
    # reducing or flipping — never margin-financed, exactly the pre-margin formula
    fee = transaction_fee(B.cost_model, notional)
    if B.cash - (notional + fee) < 0
      if O.allow_partial && (notional + fee) > 0
        qty = affordable_quantity(B.cost_model, fill_price, qty, B.cash)
        qty == 0.0 && return _reject!(B, O, date, strict)
        notional = fill_price * qty
        fee = transaction_fee(B.cost_model, notional)
      else
        return _reject!(B, O, date, strict)
      end
    end
  end

  loan_before = P.loan
  apply_trade!(P, qty, fill_price, fee; borrowed=borrowed)
  Δ = (notional + fee) - (P.loan - loan_before)   # actual cash movement, net of any loan draw/repay

  O.remaining -= qty
  if O.remaining == 0.0
    O.fulfilled = true
    O.fulfillment_date = date
  end
  B.cash -= Δ

  T = Trade(O.derivative, qty, date, -Δ)
  push!(B.history, T)

  is_closed(P) && drop!(B.portfolio, key, D)
  return B
end

"""
    process_order!(B::Broker, O::Order, check_books::Bool=true)

Strictly process a single order: remove it from the orderbook (when `check_books`) and fill
it via `execute!` with `strict=true`, so insufficient funds raise instead of being
recorded as a rejection.

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.assets[2]
O = Order(Buy(A,10))
place_order!(B,O)
Orcus.process_order!(B,O)
length(B.history)
# output

1
```
"""
function process_order!(B::Broker, O::Order, check_books::Bool=true)
  today = length(B)
  if check_books
    i = findfirst(==(O), B.orders)
    i === nothing && error("Order not in Orderbook")
    deleteat!(B.orders, i)
  else
    i = findfirst(==(O), B.orders)
    i === nothing || deleteat!(B.orders, i)
  end
  execute!(B, O, today; strict=true)
  return B
end

"""
    process_last_order!(B::Broker)

Pop and fill the most recently placed order via `execute!` (`strict=true`).
"""
function process_last_order!(B::Broker)
  isempty(B.orders) && error("No Orders to process")
  O = pop!(B.orders)
  execute!(B, O, length(B); strict=true)
  return B
end

"""

    resolve_portfolio!(B::Broker)

Close every position whose `requestToClose` flag is set, liquidating at the current market
value. Each close realizes P&L, applies transaction costs, books the cash, records a
closing `Trade`, and removes the position from the portfolio. Forced — always executes.

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.assets[2]
O = Order(Sell(A,10))
place_order!(B,O)
Orcus.process_order!(B,O)
request_to_close_all!(B)
resolve_portfolio!(B)
length(B.history)

# output

2
```

"""
function resolve_portfolio!(B::Broker)
  # Fast path: nothing has been flagged since the last resolve → skip the per-bar group scan
  # (and its dynamic dispatch) entirely. Every flag setter sets `_pending_close`.
  B._pending_close || return B
  B._pending_close = false
  today = length(B)
  pf = B.portfolio
  _close_flagged!(B, pf.buy, today)
  _close_flagged!(B, pf.sell, today)
  for g in pf.others
    _close_flagged!(B, g, today)   # barrier: closes run with a concrete Position{D}
  end
  return B
end

# Backwards walk is swap-pop-safe: closing slot i moves the (already visited) last element
# into i, so no live position is skipped.
function _close_flagged!(B::Broker, g::Group{D}, today::Int) where {D}
  i = length(g.positions)
  @inbounds while i >= 1
    P = g.positions[i]
    P.requestToClose && close_position!(B, g.keys[i], P, today)
    i -= 1
  end
  return nothing
end

"""
    close_position!(B::Broker, key, P::Position, date::Int)

Liquidate the whole of position `P` at its current market value.
"""
function close_position!(
  B::Broker, key::InstrumentKey, P::Position{D}, date::Int
) where {D<:Derivative}
  vder = value(P.derivative)                            # per-unit mark, priced once
  notional = _fx_convert(P.derivative.underlying, P.net_qty * vder)   # signed market value liquidated
  fee = transaction_fee(B.cost_model, notional)

  # reverse the whole position at the current per-unit mark; realizes P&L, nets to zero,
  # and (if margin-financed) repays the outstanding loan in full
  loan_before = P.loan
  apply_trade!(P, -P.net_qty, _fx_convert(P.derivative.underlying, vder), fee)

  Δ = notional - fee + (P.loan - loan_before)   # cash received (paid for shorts), less fees and loan repayment
  B.cash += Δ

  # net_qty is 0 after the close above, so the recorded close-trade volume is 0.0 (preserves
  # the prior behavior); the cash impact is carried by delta_cash.
  T = Trade(P.derivative, -P.net_qty, date, Δ)
  push!(B.history, T)

  drop!(B.portfolio, key, D)
  return B
end

"""
    process_orders!(B::Broker)

Process the whole orderbook in **FIFO** order via `execute!`. Orders that fully fill
(the whole book, for plain market orders) or are rejected for insufficient funds are removed;
resting limit/stop orders that don't trigger on this bar, and partially-filled orders with
quantity still outstanding, stay queued for a future bar.

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.assets[2]
O = Order(Buy(A,10))
place_order!(B,O)
process_orders!(B)
length(B.history)

# output

1

```
"""
function process_orders!(B::Broker)
  today = length(B)
  i = firstindex(B.orders)
  while i <= lastindex(B.orders)
    O = B.orders[i]
    n_rejected = length(B.rejected)
    execute!(B, O, today)
    rejected_now = length(B.rejected) > n_rejected
    (isfulfilled(O) || rejected_now) ? deleteat!(B.orders, i) : (i += 1)
  end
  return B
end

"""
    accrue_borrow_fee!(B::Broker)

Charge one bar's worth of `borrow_rate(B.margin_model)` interest against every open position's
financed exposure — `abs(value(P))` for a short, `P.loan` for a margin-financed long. No-op
under `NoMargin` (or any model with `borrow_rate == 0.0`).
"""
function accrue_borrow_fee!(B::Broker)
  B.margin_model isa NoMargin && return B
  rate = borrow_rate(B.margin_model)
  rate == 0.0 && return B
  B.cash -= accrue_fees!(B.portfolio, rate)   # type-grouped barrier: no per-position boxing
  return B
end

"""
    check_margin!(B::Broker)

If account equity (`cash + total_value(portfolio) - total_loan(portfolio)`) falls below the
aggregate maintenance requirement (`Σ abs(value(P))*maintenance_margin_pct(B.margin_model)`),
records the bar in `B.margin_calls` and liquidates the whole book via
[`request_to_close_all!`](@ref)/[`resolve_portfolio!`](@ref). No-op under `NoMargin` (or any
model with `maintenance_margin_pct == 0.0`).
"""
function check_margin!(B::Broker)
  B.margin_model isa NoMargin && return B
  pct = maintenance_margin_pct(B.margin_model)
  pct == 0.0 && return B
  requirement = total_abs_value(B.portfolio) * pct   # type-grouped barrier: no per-position boxing
  requirement == 0.0 && return B
  equity = B.cash + total_value(B.portfolio) - total_loan(B.portfolio)
  if equity < requirement
    push!(B.margin_calls, length(B))
    request_to_close_all!(B)
    resolve_portfolio!(B)
  end
  return B
end

"""
    process_all!(B::Broker)

Run one full bar for the broker: process the orderbook, resolve any pending closes, accrue
borrow fees and check margin, then record the bar's equity.

```jldoctest
Random.seed!(1);
x=asset();
y=asset();
M=market([x,y]);
B=broker(M,1000);
advance_to!(M, 1);
process_all!(B);
length(B.equity_history)
# output

1
```
"""
function process_all!(B::Broker)
  @inline
  isempty(B.orders) || process_orders!(B)        # skip the call entirely on no-order bars
  B._pending_close && resolve_portfolio!(B)      # skip the call entirely on no-close bars
  loan = 0.0
  if !(B.margin_model isa NoMargin)              # single check gates both calls below and the loan read
    accrue_borrow_fee!(B)
    check_margin!(B)
    loan = total_loan(B.portfolio)
  end
  equity = B.cash + total_value(B.portfolio) - loan   # type-grouped barrier: no per-position boxing
  push!(B.equity_history, equity)
  return B
end

"""

    status(B::Broker,digits::Int=2)

Print the status of the Broker

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
B = broker(M,1000);
status(B)

# output

========================================
Date: 3651
Cash: 1000.0
Number of orders: 0
Number of positions: 0
Number of trades: 0
========================================
```
"""
function status(B::Broker, digits::Int=2)
  otp = "="^40 * "\n" * """
       Date: $(length(B))
       Cash: $(round(B.cash;digits=digits))
       Number of orders: $(length(B.orders))
       Number of positions: $(length(B.portfolio))
       Number of trades: $(length(B.history))
       """ * "="^40
  print(otp)
  return nothing
end

"""
    request_to_close_all!(B::Broker)

Flag every open position to be closed on the next `resolve_portfolio!`/`process_all!`.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
A=B.market.assets[2];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
request_to_close_all!(B);
resolve_portfolio!(B);
length(B.history)
# output

2
```
"""
function request_to_close_all!(B::Broker)
  set_all_close!(B.portfolio)   # barrier per type-group; no per-position boxing
  B._pending_close = true
  return nothing
end

"""
    request_to_close!(B::Broker, ticker::String)

Mark all open positions for `ticker` to be closed on the next `process_all!` call.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
ticker=B.market.assets[2].ticker;
A=B.market.data[ticker];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
request_to_close!(B, ticker);
resolve_portfolio!(B);
length(B.history)
# output

2
```
"""
function request_to_close!(B::Broker, ticker::String)
  set_ticker_close!(B.portfolio, ticker)   # barrier per type-group; no per-position boxing
  B._pending_close = true
  return nothing
end

"""
    has_position(B::Broker, ticker::String)

Return `true` if the broker currently holds any open position (long or short) in `ticker`.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
ticker=B.market.assets[2].ticker;
A=B.market.data[ticker];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
has_position(B, ticker)
# output

true
```
"""
has_position(B::Broker, ticker::String) = has_position(B.portfolio, ticker)

"""
    position_direction(B::Broker, ticker::String)

Return `:long`, `:short`, or `:flat` for the current open position in `ticker`.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
ticker=B.market.assets[2].ticker;
A=B.market.data[ticker];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
position_direction(B, ticker)
# output

:long
```
"""
position_direction(B::Broker, ticker::String) = position_direction(B.portfolio, ticker)

"""
    unrealized_pnl(B::Broker) -> Float64

Total unrealized P&L (mark minus cost basis) across all currently open positions.
"""
unrealized_pnl(B::Broker) = sum(abs_return(P) for P in values(B.portfolio); init=0.0)

"""
    realized_pnl(B::Broker)

Total realized trading P&L, net of all commissions and slippage, across still-open positions.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
A=B.market.assets[2];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
realized_pnl(B)
# output

0.0
```
"""
realized_pnl(B::Broker) = sum(realized_pnl(P) for P in values(B.portfolio); init=0.0)

"""
    length(B::Broker)

Return the length of the market the Broker is operating on.
"""
length(B::Broker) = length(B.market)

"""
    cash_history(B::Broker)

Return the cash history of the Broker as a vector of `(date, cash)` tuples, one per trade
plus the opening and current balance.

```jldoctest
Random.seed!(1234);
M=market([asset(),asset()]);
T=Backtest(M,CrossOverStrategy,1000);
run_test(T);
h=cash_history(T.broker);
last(h)
# output

(3651, -18.284421217236527)
```
"""
function cash_history(B::Broker)
  cash_vector = Tuple{Int,Float64}[(length(B), B.cash)]
  cash = B.cash
  for t in reverse(B.history)
    cash -= t.delta_cash
    push!(cash_vector, (t.date, cash))
  end
  push!(cash_vector, (1, cash))
  cash_vector = reverse(cash_vector)
  return cash_vector
end

"""
    to_index(B::Broker)::Asset

Convert a Broker to an Asset

```julia
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
B = broker(M,1000);
BT = Backtest(M,CrossOverStrategy,1000)
run_test(BT)
A = to_index(BT.broker)
```

"""
function to_index(B::Broker)::Asset
  isempty(B.equity_history) && error("No equity history — run a backtest first")
  data = reshape(B.equity_history, 1, length(B.equity_history))
  Asset("Broker", data, ["Equity"])
end
