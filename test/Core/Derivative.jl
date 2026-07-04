@testset verbose=false "Derivative" begin 
@testset verbose=false "core" begin
    @testset "core.functions" begin
        ticker = "TSTS" 
        i = 1:1:100
        prp_func = (x)->0
        A = asset(ticker,i,prp_func,100,10)
        B = Buy(A, 10)
        @test u_value(B) == 100
        @test value(B) == 100
        @test abs_return(B) == -10
        @test price(B) == 110
        @test pct_return(B) <= 0
        @test log_return(B) <= 0
        @test name(B) == "Buy"
    end
    @testset "generate_derivative" begin
        @generate_derivative NewBuy x->x (val,premium)->val+premium
        x = asset()
        @test name(NewBuy(x,10)) == "NewBuy"
    end

end
end
