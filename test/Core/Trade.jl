@testset verbose=false "Test" begin
  @testset verbose=false "core" begin
    @testset "core.functions" begin
      Random.seed!(1234);
      A = asset()
      B = Buy(A, 10)
      O = order(B, 100)
      T = Trade(O, 121)
      @test T.date == 121
      @test T.volume == 100
      @test value(T) / 100 == value(A)
      @test price(T) / 100 == price(B)
    end
  end
end
