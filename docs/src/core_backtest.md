# Backtesting

`Backtest`/`run_test` drive the bar-by-bar loop; `batch_backtest` runs a threaded parameter
sweep (see the module docs on per-job market isolation); the `Tables.jl` collectors derive
Tables.jl row tables lazily from backtest output.

```@autodocs
Modules = [Orcus]
Pages = ["Core/Backtest.jl", "Core/Batch.jl", "Core/Tables.jl"]
Private = false
```

```@index
Pages = ["core_backtest.md"]
```
