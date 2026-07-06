# Orcus.jl

<!-- TODO: one-paragraph description of what Orcus is/does and who it's for -->

```@contents
Pages = ["core_data.md", "core_accounting.md", "core_derivatives.md", "core_strategy.md", "core_backtest.md", "lib.md", "analytics.md"]
Depth = 1
```

## Quick start

A strategy is two functions — `init` (run once) and `next` (run once per bar) — registered
with `@generate_strategy`. Inside them, reach the portfolio via `s.broker` and the
price data via `s.market`.

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

## Layout

<!-- TODO: short description of Core/[Market data](@ref)/[Orders & accounting](@ref)/
[Derivatives](@ref)/[Strategy authoring](@ref)/[Backtesting](@ref)/[Lib](@ref)/[Analytics](@ref) -->
