# Orders & accounting

<!-- TODO: explain order/fill/accounting path, Position netting, CostModel/MarginModel -->

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
