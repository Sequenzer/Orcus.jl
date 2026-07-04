@testset verbose=false "Strategy" begin 
@testset verbose=false "basic" begin
    Random.seed!(1234)
    x=Asset("AAPL")
    y=Asset("MSFT")
    M=Market([x,y])
    global buy_init(_::Strategy) = 3
    global buy_next(_::Strategy) = 5
    @generate_strategy BasicStrategy buy_next buy_init
    s = BasicStrategy(Broker(M,1000))
    @test isa(s,Strategy)
    @test init(s) == 3
    @test next(s) == 5
end
@testset verbose=false "1-Buy_Strategy_Test" begin 
    Random.seed!(1234)
    x=Asset("AAPL")
    y=Asset("MSFT")
    M=Market([x,y])
    global buy_init2(_::Strategy) = nothing
    global function buy_next2(s::Strategy)
        #only buy at the start every asset
        if length(s.broker.portfolio) == 0
            for (_,asset) in s.market.data
                O = Order(Buy(asset,10))
                place_order!(s.broker,O)
            end
        end
    end
    @generate_strategy BuyStrategy buy_next2 buy_init2
    s = BuyStrategy(Broker(M,1000))
    @test isa(s,Strategy)
end
end

