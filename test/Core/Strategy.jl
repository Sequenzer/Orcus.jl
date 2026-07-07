@testset verbose=false "Strategy" begin
  @testset verbose=false "basic" begin
    Random.seed!(1234)
    x=Asset("AAPL")
    y=Asset("MSFT")
    M=Market([x, y])
    global buy_init(_::Strategy) = 3
    global buy_next(_::Strategy) = 5
    @generate_strategy BasicStrategy buy_next buy_init
    s = BasicStrategy(Broker(M, 1000))
    @test isa(s, Strategy)
    @test init(s) == 3
    @test next(s) == 5
  end
  @testset verbose=false "1-Buy_Strategy_Test" begin
    Random.seed!(1234)
    x=Asset("AAPL")
    y=Asset("MSFT")
    M=Market([x, y])
    global buy_init2(_::Strategy) = nothing
    global function buy_next2(s::Strategy)
      #only buy at the start every asset
      if length(s.broker.portfolio) == 0
        for (_, asset) in s.market.data
          O = Order(Buy(asset, 10))
          place_order!(s.broker, O)
        end
      end
    end
    @generate_strategy BuyStrategy buy_next2 buy_init2
    s = BuyStrategy(Broker(M, 1000))
    @test isa(s, Strategy)
  end
  @testset verbose=false "redefinition" begin
    Random.seed!(1234)
    x = Asset("AAPL")
    M = Market([x])

    global redef_init_v1(_::Strategy) = 1
    global redef_next_v1(_::Strategy) = 10
    @generate_strategy RedefStrategy redef_next_v1 redef_init_v1

    global redef_init_v2(_::Strategy) = 2
    global redef_next_v2(_::Strategy) = 20
    @generate_strategy RedefStrategy redef_next_v2 redef_init_v2

    s = RedefStrategy(Broker(M, 1000))
    @test isa(s, Strategy)
    @test init(s) == 2
    @test next(s) == 20
    @test string(nameof(typeof(s))) == "RedefStrategy"
    @test string(typeof(s)) == "RedefStrategy"

    global RedefCollisionTarget = 5
    @test_throws LoadError eval(:(@generate_strategy RedefCollisionTarget redef_next_v1 redef_init_v1))
  end
end
