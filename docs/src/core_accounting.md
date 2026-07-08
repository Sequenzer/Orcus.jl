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
process_order!
resolve_portfolio!
process_orders!
process_all!
position_direction
unrealized_pnl(B::Broker)
realized_pnl(B::Broker)
```




```@index
Pages = ["core_accounting.md"]
```
