# Orcus.jl

A quantitative backtesting engine for Julia. Write a strategy as two functions, run it
bar-by-bar over historical data, and inspect the equity curve, trades, and portfolio.

## Install

```julia
using Pkg
Pkg.add(url="https://github.com/<your-org>/Orcus.jl")
```

Requires Julia ≥ 1.7.

## Quick start

A strategy is two functions — `init` (run once) and `next` (run once per bar) — registered
with `@generateStrategy`. Inside them, reach the portfolio via `s.broker` and the price data
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
            requestToCloseAll!(s.broker)
            placeOrder!(s.broker, Order(Buy(a, 5)))
        end
    end
end

@generateStrategy SMAcrossover cross_next cross_init

bt = Backtest(M, SMAcrossover, 10_000)   # 10k starting cash
runTest(bt)

println(bt)
status(bt.broker)
plot(bt)
```

## What's included

- **Core** — `Asset`, `Market`, `Broker`, `Order`, `Trade`, `Position`, the `Strategy`
  abstraction (`@generateStrategy`), the `Backtest` runner, and derivatives
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

MIT — see [LICENSE](LICENSE).
