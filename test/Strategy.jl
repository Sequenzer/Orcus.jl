#Test

@testset "Strategy" begin 
    Random.seed!(1234)
    x=Asset("AAPL")
end



@testset verbose=true "1-Buy_Strategy_Test" begin 
    Random.seed!(1234)
    x=Asset("AAPL")
    y=Asset("MSFT")
    M=Market([x,y])
    global buy_init(_::Strategy) = nothing
    global function buy_next(s::Strategy)
        #only buy at the start every asset
        if length(s.broker.portfolio) == 0
            for (_,asset) in s.market.data
                O = Order(Buy(asset,10))
                placeOrder!(s.broker,O)
            end
        end
    end
    @generateStrategy BuyStrategy buy_next buy_init
    T = Backtest(M, BuyStrategy, 1000)
    runTest(T)

    @testset "basic" begin
        @test T.completed == true
        @test length(T.broker.portfolio) == 2
        @test length(T.broker.orders) == 0
        @test length(T.broker.market) == length(M)
    end

    P1 = T.broker.portfolio[1]
    P2 = T.broker.portfolio[2]

    timeline = collect(keys(M.data[P1.derivative.underlying.ticker].data["Close"]))
    asset_values = collect(values(M.data[P1.derivative.underlying.ticker].data["Close"]))
    
    @testset "strategy dependent" begin
        @test P1.closed == false
        @test timeline[2] == P1.trade.date
        @test 1000 + P1.trade.delta_cash + P2.trade.delta_cash  == T.broker.cash
        @test value(P1) == last(asset_values)
    end
end






