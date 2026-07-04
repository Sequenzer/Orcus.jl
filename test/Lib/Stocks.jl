using Base: has_fast_linear_indexing
#Test
@testset verbose = false "Lib.Stocks" begin
  AAPL = load_stock("AAPL")
  GOOG = load_stock("GOOG")

  @test height(AAPL) == 8
  @test height(GOOG) == 8

  length(AAPL) == 8
  length(GOOG) == 8

  M = Market([AAPL, GOOG])
  T = Backtest(M,CrossOverStrategy,1000)
  run_test(T)
  # equity-curve recipe produces data without needing a renderer
  @test !isempty(RecipesBase.apply_recipe(Dict{Symbol,Any}(), T.broker))

end
