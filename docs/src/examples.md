# Examples

Runnable scripts in `examples/` (own environment, brings in Plots + a backend):
`julia --project=examples examples/<name>.jl`.

## Strategy basics

- **`sma_crossover.jl`** — the SMA10/SMA20 crossover strategy from the [Tutorial](tutorial.md).
- **`buy_and_hold.jl`** — a minimal strategy with an empty `next`, buying once and holding.

## Broker mechanics (no Strategy/Backtest)

- **`limit_stop.jl`** — limit/stop order mechanics and partial fills via the `Broker` API
  directly.
- **`margin.jl`** — margin/leverage/liquidation mechanics via the `Broker` API directly.

## Multi-asset / factor research

- **`pca_residual.jl`** — rolling residual PCA on a small 3-asset universe.
- **`pca_zscore.jl`** — cross-sectional PCA z-scores on a 10-asset universe.
- **`pca_multi.jl`** — multi-factor PCA across a diversified 10-asset universe.
- **`momentum_vol.jl`** — a momentum/volatility strategy over a 10-asset universe.
- **`option_wheel.jl`** — a systematic put-selling wheel strategy on dividend stocks.

## Tooling

- **`batch_sweep.jl`** — threaded parameter sweep via `batch_backtest`.
- **`dataframes_export.jl`** — exporting a backtest's `trades_table` to a `DataFrame`.
- **`backtest_profile.jl`** — allocation/timing harness for the per-bar hot path.
