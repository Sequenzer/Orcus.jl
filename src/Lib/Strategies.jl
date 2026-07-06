"""
    crossover_next(s::Strategy)

`next` for `CrossOverStrategy`: closes all positions and buys 10 units on an SMA10/SMA20
upward cross, or sells 10 units on a downward cross.
"""
function crossover_next(s::Strategy)
  for (_, asset) in s.market.data
    n = length(asset)
    n < 2 && continue
    # scalar reads: no window-slice copy per bar
    fast = asset["SMA10", n]
    slow = asset["SMA20", n]
    fast_prev = asset["SMA10", n - 1]
    slow_prev = asset["SMA20", n - 1]

    if fast > slow && fast_prev <= slow_prev
      request_to_close_all!(s.broker)
      O = Order(Buy(asset, 10))
      place_order!(s.broker, O)
    elseif fast < slow && fast_prev >= slow_prev
      request_to_close_all!(s.broker)
      O = Order(Sell(asset, 10))
      place_order!(s.broker, O)
    end
  end
end

function crossover_init(s::Strategy)
  SMA20 = IndicatorGenerator(simple_average, 20)
  SMA10 = IndicatorGenerator(simple_average, 10)
  for (_, v) in s.market.data
    apply_indicator(SMA20, v, "Close", "SMA20")
    apply_indicator(SMA10, v, "Close", "SMA10")
  end
end

@generate_strategy CrossOverStrategy crossover_next crossover_init
