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
end
