

export Strategy,
    CrossOverStrategy,
    next,
    init



abstract type Strategy end

next(s::Strategy) = error("No next method defined for Strategy \"$(typeof(s))\"")
init(s::Strategy) = error("No init method defined for Strategy \"$(typeof(s))\"")


function isaStrategy(s::Strategy)
    

end


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
next(s)

# output

next
```
"""
mutable struct CrossOverStrategy <: Strategy
    broker::Broker
    market::Market
    function CrossOverStrategy(broker::Broker)
        this = new()
        this.broker = broker
        this.market = broker.market
        return this
    end
end
function next(s::CrossOverStrategy)
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
function init(s::CrossOverStrategy)
    SMA20=IndicatorGenerator(simple_average,20)
    SMA10=IndicatorGenerator(simple_average,10)
    for (_,v) in s.market.data
        applyIndicator(SMA20,v,"Close","SMA20")
        applyIndicator(SMA10,v,"Close","SMA10")
    end
end

#=
macro generateStrategy(StrategyName::Symbol, next::Symbol, init::Symbol)
    quote
       mutable struct $StrategyName <: Strategy
            market::Market
            function $StrategyName(market::Market)
                this = new()
                this.market = market
                return this
            end
        end
    end
end

tmp_next(s::Strategy) = println("next")
tmp_init(s::Strategy) = println("init")

@generateStrategy TestStrategy tmp_next tmp_init

s = TestStrategy(Market())
=#
