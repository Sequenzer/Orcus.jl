# Orders & accounting

Orders fill deterministically FIFO in `execute!`, updating netted `Position`s (signed
`net_qty`, weighted-average `avg_cost`, `realized_pnl`) through the `Broker`; rejected
orders are recorded separately rather than silently dropped, and a `CostModel`/`MarginModel`
is applied at the fill boundary.

## Broker and Order processing

```@docs
Orcus.Broker
broker
status
length
cash_history
request_to_close_all!
place_order!
resolve_portfolio!
process_orders!
process_all!
position_direction
unrealized_pnl(B::Broker)
realized_pnl(B::Broker)
```

## Positions

```@docs
Position
Trade
abs_return(P::Position)
pct_return(P::Position)
log_return(P::Position)
value(P::Position)
value(T::Trade)
realized_pnl(P::Position)
is_closed
volume(P::Position)
```

## Orders

```@docs
Order
OrderKind
MarketOrder
Limit
Stop
order
limit_order
stop_order
isfulfilled
remaining
volume(order::Order)
request_to_close!
has_position(B::Broker, ticker::String)
```

## Portfolio

```@docs
Portfolio
total_value
total_loan
has_position(pf::Portfolio, ticker::String)
```

## Cost & margin models

```@docs
CostModel
NoCost
FlatCost
transaction_cost
MarginModel
NoMargin
RegTMargin
initial_margin_pct
maintenance_margin_pct
short_margin_rate
borrow_rate
```

```@index
Pages = ["core_accounting.md"]
```
