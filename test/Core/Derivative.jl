@testset verbose=true "Derivative" begin 
@testset verbose=true "basic" begin
    @testset "core_functions" begin
        ticker = "TSTS" 
        i = 1:1:100
        prp_func = (x)->0
        A = asset(ticker,i,prp_func,100,10)
        B = Buy(A, 10)
        @test uValue(B) == 100
        @test value(B) == 100
        @test absReturn(B) == -10
        @test price(B) == 110
        @test pctReturn(B) <= 0
        @test logReturn(B) <= 0
        @test name(B) == "Buy"
    end
    @testset "generateDerivative" begin
        @generateDerivative NewBuy x->x (val,premium)->val+premium
        x = asset()
        @test name(NewBuy(x,10)) == "NewBuy"
    end

end
end
