@testset verbose=false "Broker" begin 
@testset verbose=false "core" begin
  Random.seed!(1234);
  x=asset();
  y=asset();
  M=Market([x,y]);
  B = Broker(M,1000);
  @test B isa Broker

  B = broker(3,1000);
  isa(B,Broker)
  A = B.market.data[collect(keys(B.market.data))[2]]
  O = Order(Buy(A,10))
  placeOrder!(B,O)
  @test length(B.orders) == 1
  processOrder!(B,O)
  @test length(B.history) == 1
  @test length(B.portfolio) == 1

  requestToClose(B.portfolio[1])
  resolvePortfolio!(B)
  @test length(B.history) == 2
  @test length(B.portfolio) == 0

end

end

