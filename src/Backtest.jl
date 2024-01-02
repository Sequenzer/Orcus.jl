#test


export Backtest,
    runTest,
    processDay!

"""

    Backtest(market::Market, strategy::Strategy, cash::Real=1000)

Backtest a strategy on a market.

```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
T = Backtest(M,CrossOverStrategy,1000)
runTest(T)

# output

Backtest of CrossOverStrategy with 375.71 funds on market comprised of 2 assets.

```
"""
mutable struct Backtest
    market::Market
    broker::Broker
    strategy::Strategy
    completed::Bool
    function Backtest(market::Market, strategy::Type, cash::Real=1000)
        this = new()
        this.market = market
        this.broker = Broker(market,cash)
        this.strategy = strategy(this.broker);
        this.completed = false
        return this
    end

end



function processDay!(BT::Backtest)
    processAll!(BT.broker)
    next(BT.strategy)
    return 
end
function runTest(BT::Backtest)
    if BT.completed
        error("Backtest already completed")
    end
    # Initialize strategy
    init(BT.strategy)
    market = cutDataUntil(BT.market,end_date(BT.market))
    for i in getDomain(market)
        BT.broker.market =  cutDataUntil(market,i)
        BT.strategy.market = BT.broker.market
        #println(length(BT.broker.market))
        processDay!(BT)
    end
    BT.completed = true
    return BT
end




Base.show(io::IO,BT::Backtest) = print(io,
"""
Backtest of $(typeof(BT.strategy)) with $(round(BT.broker.cash;digits=2)) funds on market comprised of $(length(keys(BT.market.data))) assets.
""")


function plot(BT::Backtest)
    plot(BT.broker)
end





