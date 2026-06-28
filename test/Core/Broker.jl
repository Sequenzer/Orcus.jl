@testset verbose=false "Broker" begin
@testset verbose=false "core" begin
  Random.seed!(1234);
  x=asset();
  y=asset();
  M=Market([x,y]);
  B = Broker(M,1000);
  @test B isa Broker
  @test B.cost_model isa NoCost
  @test isempty(B.rejected)

  B = broker(3,1000);
  isa(B,Broker)
  A = B.market.data[collect(keys(B.market.data))[2]]
  O = Order(Buy(A,10))
  placeOrder!(B,O)
  @test length(B.orders) == 1
  processOrder!(B,O)
  @test length(B.history) == 1
  @test length(B.portfolio) == 1

  P = first(values(B.portfolio))
  requestToCloseAll!(B)
  resolvePortfolio!(B)
  @test length(B.history) == 2
  @test length(B.portfolio) == 0
end

@testset verbose=false "fifo+rejection" begin
  Random.seed!(1234);
  M = Market([asset(), asset()]);
  B = Broker(M, 1_000_000);
  A = B.market.data[collect(keys(B.market.data))[1]]

  # FIFO: orders fill front-to-back
  o1 = Order(Buy(A), 1); o2 = Order(Buy(A), 2); o3 = Order(Buy(A), 3)
  placeOrder!(B, o1); placeOrder!(B, o2); placeOrder!(B, o3)
  processOrders!(B)
  @test isempty(B.orders)
  @test [t.volume for t in B.history] == [1.0, 2.0, 3.0]   # deterministic FIFO order
  @test length(B.portfolio) == 1                            # all three netted into one

  # rejection: an order that can't be funded is recorded, not silently dropped
  Bp = Broker(M, 1.0)
  big = Order(Buy(A), 1000)
  placeOrder!(Bp, big)
  processOrders!(Bp)
  @test isempty(Bp.history)
  @test length(Bp.rejected) == 1
  @test Bp.rejected[1][1] === big
end

@testset verbose=false "cash conservation" begin
  Random.seed!(1234);
  M = Market([asset(), asset()]);
  cm = FlatCost(commission_pct=0.001, slippage_bps=5.0)
  B  = Broker(M, 1_000_000; cost_model=cm)
  A  = B.market.data[collect(keys(B.market.data))[1]]

  start = B.cash
  O = Order(Buy(A, 10))
  placeOrder!(B, O); processOrders!(B)
  P = first(values(B.portfolio))
  requestToCloseAll!(B); resolvePortfolio!(B)

  # round trip at the same bar: final cash == start minus total fees, and < start
  @test B.cash < start
  total_fees = start - B.cash
  @test total_fees > 0
  @test isempty(B.portfolio)
end
end
