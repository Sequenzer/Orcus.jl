# Orcus.jl

[![CI](https://github.com/Sequenzer/Orcus.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Sequenzer/Orcus.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/Sequenzer/Orcus.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/Sequenzer/Orcus.jl)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://sequenzer.github.io/Orcus.jl/dev)

Orcus.jl is a backtesting engine for quantitative finance written in Julia, focused on
research and signal authoring: PCA factor models, rolling statistics, technical indicators,
and a lightweight two-function strategy abstraction. Write a strategy as `init`/`next`, run it
bar-by-bar over historical data, and inspect the equity curve, trades, and portfolio.

> **Status:** pre-alpha. APIs may still change, the time model is daily-bar only, and
> execution realism is intentionally limited (market orders only; margin and multi-currency
> support exist but are lightweight, not execution-accounting-grade). See the docs for the
> current gap analysis.

## Install

Orcus.jl is not yet registered. Add it directly from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/Sequenzer/Orcus.jl")
```

Requires Julia ≥ 1.10.

## Documentation

The documentation is available at [Orcus.dev](https://sequenzer.github.io/Orcus.jl/dev), you can find a tutorial, examples, and API reference there.

## Quick start


```julia
using Orcus

M = market([GOOG])          # built-in sample data; see available_stocks()

function cross_init(s::Strategy)
  a = s.market["GOOG"]
  apply_indicator(IndicatorGenerator(simple_average, 10), a, "Close", "SMA10")
  apply_indicator(IndicatorGenerator(simple_average, 20), a, "Close", "SMA20")
end

function cross_next(s::Strategy)
  a = s.market["GOOG"]
  n = length(a)
  n < 2 && return
  crossed_up = a["SMA10", n] > a["SMA20", n] && a["SMA10", n-1] <= a["SMA20", n-1]
  if crossed_up
    request_to_close_all!(s.broker)
    place_order!(s.broker, Order(Buy(a, 5)))
  end
end

@generate_strategy SMAcrossover cross_next cross_init

bt = Backtest(M, SMAcrossover, 10_000)   # 10k starting cash
run_test(bt)

status(bt.broker)    # show the final status of the backtest
```

## What's included

- **Core** — the engine: price data containers with zero-copy bar advancement, the
  order/fill/accounting path (FIFO fills, netted positions, pluggable cost/margin models),
  derivatives (`Buy`/`Sell`/`LongCall`/`LongPut`/`ShortCall`/`ShortPut`), the `@generate_strategy`
  authoring model, and the backtest runner.
- **Lib** — sample data loaders (`load_stock`, `load_stocks`, `available_stocks`) and example
  strategies.
- **Analytics** — rolling PCA (residual/zscore/multi-factor), rolling statistics, technical
  indicators, options pricing, and a performance-stats suite (Sharpe, Sortino, Calmar, VaR,
  CVaR, Omega, Ulcer index, information ratio).

See `examples/` for runnable strategies, including the SMA-crossover shown above.

## License

Orcus.jl is free software, licensed under the **GNU General Public License v3.0** — see
[LICENSE](LICENSE).

You may use, study, share, and modify it freely, including for private and educational
purposes. The copyleft terms require that any distributed derivative work is also released
under the GPLv3, so everyone downstream keeps the same freedoms.

    Copyright (C) 2022 Marcel Wack <wack@math.tu-berlin.de> and contributors

    This program is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free Software
    Foundation, either version 3 of the License, or (at your option) any later
    version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
    PARTICULAR PURPOSE. See the GNU General Public License for more details.
