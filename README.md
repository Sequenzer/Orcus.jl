# Orcus.jl

[![CI](https://github.com/Sequenzer/Orcus.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Sequenzer/Orcus.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/Sequenzer/Orcus.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/Sequenzer/Orcus.jl)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://sequenzer.github.io/Orcus.jl/dev)

A quantitative backtesting engine for Julia. Write a strategy as two functions, run it
bar-by-bar over historical data, and inspect the equity curve, trades, and portfolio.

## Install

```julia
using Pkg
Pkg.add(url="https://github.com/<your-org>/Orcus.jl")
```

Requires Julia ≥ 1.10.

## Quick start

A strategy is two functions — `init` (run once) and `next` (run once per bar) — registered
with `@generate_strategy`. Inside them, reach the portfolio via `s.broker` and the price data
via `s.market`.

```julia
using Orcus

M = market([GOOG])          # built-in sample data; see available_stocks()

function cross_init(s::Strategy)
    for (_, a) in s.market.data
        apply_indicator(IndicatorGenerator(simple_average, 10), a, "Close", "SMA10")
        apply_indicator(IndicatorGenerator(simple_average, 20), a, "Close", "SMA20")
    end
end

function cross_next(s::Strategy)
    for (_, a) in s.market.data
        n = length(a)
        n < 2 && continue
        crossed_up = a["SMA10", n] > a["SMA20", n] && a["SMA10", n-1] <= a["SMA20", n-1]
        if crossed_up
            request_to_close_all!(s.broker)
            place_order!(s.broker, Order(Buy(a, 5)))
        end
    end
end

@generate_strategy SMAcrossover cross_next cross_init

bt = Backtest(M, SMAcrossover, 10_000)   # 10k starting cash
run_test(bt)

println(bt)
status(bt.broker)
plot(bt)
```

## What's included

- **Core** — `Asset`, `Market`, `Broker`, `Order`, `Trade`, `Position`, the `Strategy`
  abstraction (`@generate_strategy`), the `Backtest` runner, and derivatives
  (`Buy`/`Sell`/`LongCall`/`LongPut`/`ShortCall`/`ShortPut`).
- **Lib** — sample stock data loaders (`load_stock`, `load_stocks`, `available_stocks`) and
  example strategies.
- **Analytics** — rolling PCA factor models, rolling-window statistics, technical indicators,
  and option-pricing helpers.

See `examples/` for runnable strategies: `buy_and_hold.jl`, `sma_crossover.jl`,
`momentum_vol.jl`, `option_wheel.jl`, and the PCA strategies (`pca_residual.jl`,
`pca_multi.jl`, `pca_zscore.jl`).

## Tests

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

## License

Orcus.jl is free software, licensed under the **GNU General Public License v3.0** — see
[LICENSE](LICENSE).

You may use, study, share, and modify it freely, including for private and educational
purposes. The copyleft terms require that any distributed derivative work is also released
under the GPLv3, so everyone downstream keeps the same freedoms.

    Copyright (C) 2022 Marcel Wack <wac.marcel@gmail.com> and contributors

    This program is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free Software
    Foundation, either version 3 of the License, or (at your option) any later
    version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
    PARTICULAR PURPOSE. See the GNU General Public License for more details.
