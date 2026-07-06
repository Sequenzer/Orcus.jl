# Orcus.jl

Welcome to the Orcus.jl documentation! Orcus is a Julia package for backtesting and analyzing trading strategies. 
Orcus was spun out of a private research project and is now open source. It is designed to be simple, flexible, and extensible, allowing users to easily implement and test their own trading strategies.
It is in many ways a "research framework" and can be opinionated about how to structure a backtest, but it is also designed to be flexible enough to accommodate a wide range of use cases.
It is optimized for big universes and will show its strength when backtesting multidimensional strategies.

## Feel free to reach out!

As it is with many backtesting frameworks, it will probably not be a perfect fit for your use case. If you have any questions, suggestions, or feedback, please feel free to reach out to me [Marcel Wack](mailto:wack@math.tu-berlin.de).

## Getting started

The best way to get started is to read the [tutorial](tutorial.md) and then dive into the [examples](examples.md). The examples are a good way to see how to use Orcus in practice.
But if you want to get started without much reading, lets look at a simple example of a moving average crossover strategy.

The core functionality of Orcus is the '@generate_strategy' macro, which allows you to define a strategy in a simple and intuitive way.
Strategies are defined as two functions: `init` and `next`.
The `init` function is run once at the beginning of the backtest, and the `next` function is run once per bar (i.e., for each time step in the backtest).

First of all lets start up Orcus and load some sample data.

```julia
using Orcus

M = market([GOOG])          # creating a market object with singular GOOG ticker
```

We now define two simple indicators, a 10-day and a 20-day simple moving average (SMA). The `init` function is used to apply these indicators to the market data.

```julia
function cross_init(s::Strategy)
  for (_, a) in s.market.data
    apply_indicator(IndicatorGenerator(simple_average, 10), a, "Close", "SMA10")
    apply_indicator(IndicatorGenerator(simple_average, 20), a, "Close", "SMA20")
  end
end
```

Next lets define the `next` function, which will be called for each bar in the backtest. 
In this function, we check if the 10-day SMA has crossed above the 20-day SMA. If it has, we close any existing positions and place a new buy order for 5 shares of GOOG.

```julia
function cross_next(s::Strategy)
  a = s.market.data[GOOG]  # Access the data for GOOG
  n = length(a)
  n < 2 && continue  # Not enough data to check for crossover

  crossed_up = a["SMA10", n] > a["SMA20", n] && a["SMA10", n-1] <= a["SMA20", n-1]

  if crossed_up
    request_to_close_all!(s.broker)
    place_order!(s.broker, Order(Buy(a, 5)))
  end
end
```

What is left todo is to register the strategy with the `@generate_strategy` macro, create a backtest object, and run the backtest.

```julia
@generate_strategy SMAcrossover cross_next cross_init

bt = Backtest(M, SMAcrossover, 10_000)   # 10k starting cash
run_test(bt)
```

<!-- TODO: short description of Core/[Market data](@ref)/[Orders & accounting](@ref)/
[Derivatives](@ref)/[Strategy authoring](@ref)/[Backtesting](@ref)/[Lib](@ref)/[Analytics](@ref) -->
