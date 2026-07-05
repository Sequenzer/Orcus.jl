@testset verbose=false "Netting" begin
  @testset "two buys net into one position" begin
    Random.seed!(1234);
    M = Market([asset(), asset()]);
    B = Broker(M, 1_000_000);
    A = B.market.data[collect(keys(B.market.data))[1]]

    d1 = Buy(A);
    d2 = Buy(A)
    place_order!(B, Order(d1, 10))
    place_order!(B, Order(d2, 10))
    process_orders!(B)

    @test length(B.portfolio) == 1
    P = first(values(B.portfolio))
    @test P.net_qty == 20.0
    @test P.avg_cost ≈ (price(d1)*10 + price(d2)*10) / 20
  end

  @testset "buy and sell are distinct instruments" begin
    Random.seed!(1234);
    M = Market([asset(), asset()]);
    B = Broker(M, 1_000_000);
    A = B.market.data[collect(keys(B.market.data))[1]]

    place_order!(B, Order(Buy(A), 10))
    place_order!(B, Order(Sell(A), 10))
    process_orders!(B)
    @test length(B.portfolio) == 2     # Buy and Sell do not net against each other
  end

  @testset "options with different strikes stay separate" begin
    Random.seed!(1234);
    M = Market([asset(), asset()]);
    B = Broker(M, 1_000_000);
    A = B.market.data[collect(keys(B.market.data))[1]]

    spot = value(A)
    place_order!(B, Order(LongCall(A, spot), 1))
    place_order!(B, Order(LongCall(A, spot + 5), 1))
    place_order!(B, Order(LongCall(A, spot), 1))   # same strike → nets with the first
    process_orders!(B)

    @test length(B.portfolio) == 2
    keys_present = keys(B.portfolio)
    @test instrument_key(LongCall(A, spot)) in keys_present
    @test instrument_key(LongCall(A, spot + 5)) in keys_present
  end

  @testset "round-trip directions: long and short close correctly" begin
    Random.seed!(1234);
    M = Market([asset(), asset()]);
    B = Broker(M, 1_000_000);
    A = B.market.data[collect(keys(B.market.data))[1]]

    place_order!(B, Order(Buy(A), 10))
    place_order!(B, Order(Sell(A), 10))
    process_orders!(B)
    @test position_direction(B, A.ticker) in (:long, :short)
    @test has_position(B, A.ticker)

    request_to_close_all!(B)
    resolve_portfolio!(B)
    @test isempty(B.portfolio)
    @test position_direction(B, A.ticker) == :flat
    @test !has_position(B, A.ticker)
  end
end
