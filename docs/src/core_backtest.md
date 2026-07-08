# Backtesting

`Backtest`/`run_test` drive the bar-by-bar loop for a single strategy; `batch_backtest`
runs a threaded parameter sweep over per-job-copied markets; and the Tables.jl collectors
(`trades_table`, `weights_table`, `turnover_table`) derive row tables from a completed run
on demand, with no per-bar cost.

```@index
Pages = ["core_backtest.md"]
```
