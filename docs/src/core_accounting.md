# Orders & accounting

The order/fill/accounting path: a single deterministic FIFO fill in `execute!`, netted
`Position`s keyed by `(ticker, type, strike, expiry)`, and pluggable `CostModel`/`MarginModel`
applied per fill.

```@autodocs
Modules = [Orcus]
Pages = [
  "Core/Order.jl",
  "Core/Trade.jl",
  "Core/Position.jl",
  "Core/Portfolio.jl",
  "Core/Broker.jl",
  "Core/Cost.jl",
  "Core/Margin.jl",
]
Private = false
```

```@index
Pages = ["core_accounting.md"]
```
