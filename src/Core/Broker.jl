
export
    Broker,
    broker,
    placeOrder!,
    execute!,
    processOrder!,
    processLastOrder!,
    processOrders!,
    resolvePortfolio!,
    processAll!,
    requestToCloseAll!,
    requestToClose!,
    has_position,
    position_direction,
    unrealized_pnl,
    realized_pnl,
    cash_history,
    toIndex,
    status




"""

    Broker(market::Market, cash::Real; cost_model::CostModel=NoCost())

The order-executing unit of the system. Holds cash, a `Market`, a pluggable transaction
`cost_model`, a netted `portfolio` (keyed by `instrument_key`), the open `orders` queue
(FIFO), the executed-trade `history`, a list of `rejected` orders, and the `equity_history`.

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
    portfolio::Portfolio                           # positions grouped by concrete derivative type
    orders::Vector{Order}                          # FIFO queue
    history::Vector{Trade}
    rejected::Vector{Tuple{Order,String,Int}}      # (order, reason, bar)
    equity_history::Vector{Float64}
    _close_keys::Vector{InstrumentKey}             # reusable scratch for resolvePortfolio!
    _pending_close::Bool                           # set when a close is requested; lets resolvePortfolio! skip the per-bar scan
    function Broker(market::Market, cash::Real; cost_model::CostModel=NoCost())
        this = new()
        this.cash           = Float64(cash)
        this.market         = market
        this.cost_model     = cost_model
        this.portfolio      = Portfolio()
        this.orders         = Vector{Order}()
        this.history        = Vector{Trade}()
        this.rejected       = Tuple{Order,String,Int}[]
        this.equity_history = Float64[]
        this._close_keys    = InstrumentKey[]
        this._pending_close = false
        return this
    end
end

broker(market::Market, cash::Real; cost_model::CostModel=NoCost()) =
    Broker(market, cash; cost_model=cost_model)

function broker(n_Assets::Int, cash::Real; cost_model::CostModel=NoCost())
    M=market();
    foreach(x->addAsset!(M,asset()),1:n_Assets)
    return Broker(M, cash; cost_model=cost_model)
end

Base.show(io::IO,B::Broker) = print(io,"Broker with $(round(B.cash;digits=2)) funds and $(length(B.orders)) open orders")

"""

    placeOrder!(B::Broker,O::Order)

Place an Order in the Broker's Orderbook

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
B
```
"""
function placeOrder!(B::Broker,O::Order)
     #ToDo Check if requirements for placement are met
    push!(B.orders,O)
    return;
end


"""
    execute!(B::Broker, O::Order, date::Int=length(B); strict::Bool=false)

The single fill path used by every order-processing function. Applies the broker's
`cost_model`, checks funds, books the cash impact, records the `Trade`, and folds the
fill into the netted `Position` for `instrument_key(O.derivative)`.

- gross `notional = price(O)` (signed; negative for `Sell`/short legs);
- `(commission, slippage) = transaction_cost(B.cost_model, notional)`; fees always worsen
  the fill, so the cash that leaves the account is `Δ = notional + commission + slippage`;
- if `B.cash - Δ < 0` the order is **rejected** (recorded in `B.rejected`) unless
  `strict=true`, in which case it errors — preserving the old `processOrder!` contract;
- the position is created on first fill and **deleted** from the portfolio when it nets to
  zero. The per-unit fill price handed to `apply_trade!` is the raw `price(O.derivative)`;
  total fees are passed separately and subtracted from the position's `realized_pnl`.
"""
function execute!(B::Broker, O::Order{D}, date::Int=length(B); strict::Bool=false) where {D<:Derivative}
    if isfulfilled(O)
        strict && error("Order already fulfilled")
        return B
    end
    notional = price(O)                                   # signed gross
    c        = transaction_cost(B.cost_model, notional)
    fee      = c.commission + c.slippage
    Δ        = notional + fee                             # cash out of the account

    if B.cash - Δ < 0
        strict && error("Insufficient funds")
        push!(B.rejected, (O, "insufficient funds", date))
        return B
    end

    fulfill(O, date)
    B.cash -= Δ

    T = Trade(O, date)
    T.delta_cash = -Δ
    push!(B.history, T)

    key = instrument_key(O.derivative)
    P   = get_or_create!(B.portfolio, key, O.derivative)  # typed Position{D}
    P.derivative = O.derivative                           # refresh mark-to-market reference
    apply_trade!(P, O.volume, price(O.derivative), fee)
    is_closed(P) && drop!(B.portfolio, key, D)
    return B
end


"""
    processOrder!(B::Broker, O::Order, check_books::Bool=true)

Strictly process a single order: remove it from the orderbook (when `check_books`) and fill
it via [`execute!`](@ref) with `strict=true`, so insufficient funds raise instead of being
recorded as a rejection.

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
processOrder!(B,O)
length(B.history)
```
"""
function processOrder!(B::Broker, O::Order, check_books::Bool=true)
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
    processLastOrder!(B::Broker)

Pop and fill the most recently placed order via [`execute!`](@ref) (`strict=true`).
"""
function processLastOrder!(B::Broker)
    isempty(B.orders) && error("No Orders to process")
    O = pop!(B.orders)
    execute!(B, O, length(B); strict=true)
    return B
end

"""

    resolvePortfolio!(B::Broker)

Close every position whose `requestToClose` flag is set, liquidating at the current market
value. Each close realizes P&L, applies transaction costs, books the cash, records a
closing `Trade`, and removes the position from the portfolio. Forced — always executes.

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Sell(A,10))
placeOrder!(B,O)
processOrder!(B,O)
requestToCloseAll!(B)
resolvePortfolio!(B)
length(B.history)

# output

2
```

"""
function resolvePortfolio!(B::Broker)
    # Fast path: nothing has been flagged since the last resolve → skip the per-bar group scan
    # (and its dynamic dispatch) entirely. Every flag setter sets `_pending_close`.
    B._pending_close || return B
    # Scan for flagged positions without per-position boxing (barrier per type-group); only
    # when something is flagged do we collect its keys into a reused buffer so we can mutate
    # the portfolio safely while closing.
    collect_flagged!(B._close_keys, B.portfolio)
    B._pending_close = false
    isempty(B._close_keys) && return B
    today = length(B)
    for key in B._close_keys
        close_position!(B, key, B.portfolio[key], today)
    end
    return B
end

"""
    close_position!(B::Broker, key, P::Position, date::Int)

Liquidate the whole of position `P` at its current market value. Internal close-out helper
used by [`resolvePortfolio!`](@ref).
"""
function close_position!(B::Broker, key::InstrumentKey, P::Position, date::Int)
    notional = value(P)                                   # signed market value liquidated
    c        = transaction_cost(B.cost_model, notional)
    fee      = c.commission + c.slippage

    # reverse the whole position at the current per-unit mark; realizes P&L, nets to zero
    apply_trade!(P, -P.net_qty, value(P.derivative), fee)

    Δ = notional - fee                                    # cash received (paid for shorts), less fees
    B.cash += Δ

    # net_qty is 0 after the close above, so the recorded close-trade volume is 0.0 (preserves
    # the prior behavior); the cash impact is carried by delta_cash.
    T = Trade(P.derivative, -P.net_qty, date, Δ)
    push!(B.history, T)

    delete!(B.portfolio, key)
    return B
end



"""
    processOrders!(B::Broker)

Process the whole orderbook in **FIFO** order via [`execute!`](@ref). Unfillable orders are
recorded in `B.rejected` rather than silently discarded. The queue is empty on return.

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
processOrders!(B)
length(B.history)

# output

1

```
"""
function processOrders!(B::Broker)
    today = length(B)
    while !isempty(B.orders)
        O = popfirst!(B.orders)                           # FIFO
        execute!(B, O, today)
    end
    return B
end

function processAll!(B::Broker)
    @inline
    isempty(B.orders) || processOrders!(B)        # skip the call entirely on no-order bars
    B._pending_close  && resolvePortfolio!(B)      # skip the call entirely on no-close bars
    equity = B.cash + total_value(B.portfolio)     # type-grouped barrier: no per-position boxing
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
function status(B::Broker,digits::Int=2)
    otp ="="^40*"\n"*"""
    Date: $(length(B))
    Cash: $(round(B.cash;digits=digits))
    Number of orders: $(length(B.orders))
    Number of positions: $(length(B.portfolio))
    Number of trades: $(length(B.history))
    """*"="^40
    print(otp)
    return
end

"""
    requestToCloseAll!(B::Broker)

Flag every open position to be closed on the next `resolvePortfolio!`/`processAll!`.
"""
function requestToCloseAll!(B::Broker)
    set_all_close!(B.portfolio)   # barrier per type-group; no per-position boxing
    B._pending_close = true
    return
end

"""
    requestToClose!(B::Broker, ticker::String)

Mark all open positions for `ticker` to be closed on the next `processAll!` call.
"""
function requestToClose!(B::Broker, ticker::String)
    for P in values(B.portfolio)
        P.derivative.underlying.ticker == ticker && requestToClose(P)
    end
    B._pending_close = true
    return
end

"""
    has_position(B::Broker, ticker::String) -> Bool

Return `true` if the broker currently holds any open position (long or short) in `ticker`.
"""
has_position(B::Broker, ticker::String) =
    any(P -> P.derivative.underlying.ticker == ticker && !is_closed(P), values(B.portfolio))

"""
    position_direction(B::Broker, ticker::String) -> Symbol

Return `:long`, `:short`, or `:flat` for the current open position in `ticker`. Direction is
taken from the sign of `value(P)` so it is correct for both `Buy`/`Sell` legs and options.
"""
function position_direction(B::Broker, ticker::String)
    for P in values(B.portfolio)
        (P.derivative.underlying.ticker == ticker && !is_closed(P)) || continue
        v = value(P)
        return v > 0 ? :long : v < 0 ? :short : :flat
    end
    return :flat
end

"""
    unrealized_pnl(B::Broker) -> Float64

Total unrealized P&L (mark minus cost basis) across all currently open positions.
"""
unrealized_pnl(B::Broker) =
    sum(absReturn(P) for P in values(B.portfolio); init=0.0)

"""
    realized_pnl(B::Broker) -> Float64

Total realized trading P&L, net of all commissions and slippage, across open positions.
Note: fully closed positions are dropped from the portfolio, so this tracks realized P&L
still attached to live instruments.
"""
realized_pnl(B::Broker) =
    sum(realized_pnl(P) for P in values(B.portfolio); init=0.0)

"""
    length(B::Broker)

Return the length of the market the Broker is operating on.
"""
length(B::Broker) = length(B.market)

"""
    cash_history(B::Broker)

Return the cash history of the Broker

# Example
```julia
Random.seed!(1234);
M=market([asset(),asset()]);
T = Backtest(M,CrossOverStrategy,1000)
runTest(T)
cash_history(T.broker)
```
"""
function cash_history(B::Broker)
    cash_vector = Tuple{Int, Real}[(length(B),B.cash)]
    cash = B.cash
    for t in reverse(B.history)
        cash -= t.delta_cash
        push!(cash_vector,(t.date,cash))
    end
    push!(cash_vector,(1,cash))
    cash_vector = reverse(cash_vector)
    return cash_vector
end

"""
    toIndex(B::Broker)::Asset

Convert a Broker to an Asset

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
B = broker(M,1000);
BT = Backtest(M,CrossOverStrategy,1000)
runTest(BT)
A = toIndex(BT.broker)
```

"""
function toIndex(B::Broker)::Asset
    isempty(B.equity_history) && error("No equity history — run a backtest first")
    data = reshape(B.equity_history, 1, length(B.equity_history))
    Asset("Broker", data, ["Equity"])
end
