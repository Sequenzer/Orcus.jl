
export crossover_init,
  crossover_next

"""
    
    CrossOverStrategy(broker::Broker)

An SMA10/SMA20 crossover strategy: buy on an upward cross, sell on a downward cross.

## Example
```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
B = broker(M,1000);
s = CrossOverStrategy(B)
init(s)
x.data
print(x)
collect(x.data["SMA10"])[end]

# output

```
"""
function crossover_next(s::Strategy)
  for (_, asset) in s.market.data
    sma10 = asset["SMA10"]
    sma20 = asset["SMA20"]

    if length(sma10) < 2
      continue
    end
    ismissing(sma10[end]) && continue
    ismissing(sma20[end]) && continue
    ismissing(sma10[end - 1]) && continue
    ismissing(sma20[end - 1]) && continue

    if sma10[end] > sma20[end] && sma10[end - 1] <= sma20[end - 1]
      request_to_close_all!(s.broker)
      O = Order(Buy(asset, 10))
      place_order!(s.broker, O)
    elseif sma10[end] < sma20[end] && sma10[end - 1] >= sma20[end - 1]
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
