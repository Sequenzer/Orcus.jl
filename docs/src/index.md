# Orcus.jl

Welcome to the Orcus.jl documentation! Orcus is a Julia package for backtesting and analyzing trading strategies. 
Orcus was spun out of a private research project and is now open source. It is designed to be simple, flexible, and extensible, allowing users to easily implement and test their own trading strategies.
It is in many ways a "research framework" and can be opinionated about how to structure a backtest, but it is also designed to be flexible enough to accommodate a wide range of use cases.
It is optimized for big universes and will show its strength when backtesting multidimensional strategies.

## Feel free to reach out!

As it is with many backtesting frameworks, it will probably not be a perfect fit for your use case. If you have any questions, suggestions, or feedback, please feel free to reach out to me [Marcel Wack](mailto:wack@math.tu-berlin.de).

## Getting started

The best way to get started is to read the [tutorial](tutorial.md), which builds a simple
SMA-crossover strategy end to end, and then dive into the [examples](examples.md) for more
elaborate strategies and order-book mechanics.

## Reference

- [Market data](@ref) — `Asset`/`Market` price-data containers, sample-data loaders, and
  zero-copy bar advancement.
- [Orders & accounting](@ref) — the `Broker`, order/fill processing, and position/P&L
  accounting.
- [Derivatives](@ref) — `Buy`/`Sell`/option types and the `payoff` dispatch that prices
  them.
- [Strategy authoring](@ref) — the `init`/`next` model and `@generate_strategy`.
- [Backtesting](@ref) — `Backtest`/`run_test`, `batch_backtest` sweeps, and the Tables.jl
  output collectors.
- [Lib](@ref) — bundled sample tickers/loaders and the example `CrossOverStrategy`.
- [Analytics](@ref) — PCA factor models, rolling stats, performance metrics, indicators,
  and options.
