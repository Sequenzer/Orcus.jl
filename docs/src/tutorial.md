# Tutorial

Orcus's core functionality is the `@generate_strategy` macro, which lets you define a
strategy as two functions: `init`, run once at the start of the backtest, and `next`, run
once per bar. Let's walk through a simple SMA-crossover strategy.

First, start up Orcus and load some sample data.

```julia
using Orcus

M = market([GOOG])          # creating a market object with singular GOOG ticker
```

Next, define two simple indicators: a 10-day and a 20-day simple moving average (SMA). The
`init` function attaches these indicators to the market data.

```julia
function cross_init(s::Strategy)
  for (_, a) in s.market.data
    apply_indicator(IndicatorGenerator(simple_average, 10), a, "Close", "SMA10")
    apply_indicator(IndicatorGenerator(simple_average, 20), a, "Close", "SMA20")
  end
end
```

Now define the `next` function, called for each bar in the backtest. It checks whether the
10-day SMA has crossed above the 20-day SMA; if it has, it closes any existing positions and
places a new buy order for 5 shares of GOOG.

```julia
function cross_next(s::Strategy)
  a = s.market.data["GOOG"]  # Access the data for GOOG
  n = length(a)
  n < 2 && return  # Not enough data to check for crossover

  crossed_up = a["SMA10", n] > a["SMA20", n] && a["SMA10", n-1] <= a["SMA20", n-1]

  if crossed_up
    request_to_close_all!(s.broker)
    place_order!(s.broker, Order(Buy(a, 5)))
  end
end
```

What's left is to register the strategy with `@generate_strategy`, create a `Backtest`, and
run it.

```julia
@generate_strategy SMAcrossover cross_next cross_init

bt = Backtest(M, SMAcrossover, 10_000)   # 10k starting cash
run_test(bt)
```

From here, [Examples](examples.md) has more strategies covering multi-asset universes, PCA
factor models, and order-book mechanics, and the Core pages document the pieces used above
in full: [Market data](@ref), [Strategy authoring](@ref), and [Backtesting](@ref).
