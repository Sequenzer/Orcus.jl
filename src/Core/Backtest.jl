
export Backtest,
    runTest,
    processDay!

"""

    Backtest(market::Market, strategy::Strategy, cash::Real=1000)

Backtest a strategy on a market.

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
T = Backtest(M,CrossOverStrategy,1000)
runTest(T)

# output

Backtest of CrossOverStrategy with 375.71 funds on market comprised of 2 assets.

```
"""
mutable struct Backtest{T<:Strategy}
    market::Market
    broker::Broker
    strategy::T
    completed::Bool
    function Backtest(market::Market, strategy::Type, cash::Real=1000)
        this = new{strategy}()
        this.market = market
        this.broker = Broker(market,cash)
        this.strategy = strategy(this.broker);
        this.completed = false
        return this
    end

end

backtest(market::Market, strategy::Type, cash::Real=1000) = Backtest(market,strategy,cash)



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
    B = BT.broker
    base_market = copy(BT.market)

    for i in 1:length(base_market)
       set_data_to!(B.market,base_market,1:i)
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





