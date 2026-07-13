@testset verbose=false "Derivative" begin
  @testset verbose=false "core" begin
    @testset "core.functions" begin
      ticker = "TSTS"
      i = 1:1:100
      A = asset(ticker, i, 0.0, 0.0, 100, 10)
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
      @generate_derivative NewBuy x->x (val, premium)->val+premium
      x = asset()
      @test name(NewBuy(x, 10)) == "NewBuy"
    end
    @testset "generate_derivative redefinition" begin
      @generate_derivative RedefDeriv x->x (val, premium)->val+premium
      @generate_derivative RedefDeriv x->2x (val, premium)->val+premium

      x2 = asset()
      d = RedefDeriv(x2, 10)
      @test name(d) == "RedefDeriv"
      @test payoff(d, 5) == 10

      global RedefDerivCollision = 5
      @test_throws LoadError eval(
        :(@generate_derivative RedefDerivCollision x->x (val, premium)->val+premium)
      )
    end
  end
end
