# Market data

`Asset` holds one instrument's OHLC-style price matrix and indicator columns; `Market` is a
collection of `Asset`s keyed by ticker. Bar advancement is zero-copy — see `advance_to!`.

```@autodocs
Modules = [Orcus]
Pages = ["Core/Asset.jl", "Core/Market.jl", "Core/Utils.jl", "Core/Indicator.jl"]
Private = false
```

```@index
Pages = ["core_data.md"]
```
