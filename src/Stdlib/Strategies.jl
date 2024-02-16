


export crossover_init,
    crossover_next





"""
    
    CrossOverStrategy(broker::Broker)

A temporary strategy for testing purposes.

## Example
```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
M.data
B = Broker(M,1000);
s = CrossOverStrategy(B)
init(s)
print(x)
collect(x.data["SMA10"])[end]

# output

```
"""
function crossover_next(s::Strategy)
    for (_,asset) in s.market.data
        sma10 = collect(values(asset.data["SMA10"]))
        sma20 = collect(values(asset.data["SMA20"]))

        if length(sma10) < 2
            continue
        end
        ismissing(sma10[end]) && continue
        ismissing(sma20[end]) && continue
        ismissing(sma10[end-1]) && continue
        ismissing(sma20[end-1]) && continue

        if sma10[end] > sma20[end] && sma10[end-1] <=sma20[end-1]
            requestToCloseAll!(s.broker)
            O = Order(Buy(asset,10))
            placeOrder!(s.broker,O)
        elseif sma10[end] < sma20[end] && sma10[end-1] >= sma20[end-1]
            requestToCloseAll!(s.broker)
            O = Order(Sell(asset,10))
            placeOrder!(s.broker,O)
        end
    end
end

function crossover_init(s::Strategy)
    SMA20=IndicatorGenerator(simple_average,20)
    SMA10=IndicatorGenerator(simple_average,10)
    for (_,v) in s.market.data
        applyIndicator(SMA20,v,"Close","SMA20")
        applyIndicator(SMA10,v,"Close","SMA10")
    end
end



@generateStrategy CrossOverStrategy crossover_next crossover_init





