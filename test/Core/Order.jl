@testset "Order" begin
        A=asset();
        B=Buy(A,10);
        O=order(B);
        @test O.fulfilled == false
        @test isfulfilled(O) == false
        Int(floor(price(O))) == 118
        fulfill(O,100)
        @test O.fulfilled == true
        @test isfulfilled(O) == true

@testset "kinds" begin
        A=asset();
        D=Buy(A,10);

        O = Order(D,5)
        @test O.kind isa MarketOrder
        @test O.allow_partial == false
        @test remaining(O) == O.volume == 5.0

        L = limit_order(D,5,95.0)
        @test L.kind isa Limit
        @test L.kind.price == 95.0
        @test remaining(L) == 5.0

        S = stop_order(D,5,105.0; allow_partial=true)
        @test S.kind isa Stop
        @test S.kind.price == 105.0
        @test S.allow_partial == true
end
end
