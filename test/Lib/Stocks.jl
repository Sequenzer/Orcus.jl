@testset verbose = false "Lib.Stocks" begin
  @testset "load_stock" begin
    A = load_stock("AAPL")
    G = load_stock("GOOG")
    @test height(A) == 6
    @test height(G) == 6
  end

  @testset "load_stocks shared grid" begin
    M = load_stocks(["AAPL", "GOOG"])
    @test has_axis(M)
    n = length(M.axis)
    for a in M.assets
      @test size(a.data, 2) == n
    end
    # AAPL trades since 1980, GOOG since 2004: grid start is AAPL-only
    @test timestamp(M, 1) == DateTime(1980, 12, 12)
    @test isnan(M["GOOG"]["Close", 1])
    @test !isnan(M["AAPL"]["Close", 1])
    # known closes land at their dates
    @test M["AAPL"]["Close", bar_of(M, Date(2020, 7, 2))] == 364.1099853515625
    @test M["GOOG"]["Close", bar_of(M, Date(2004, 8, 19))] == 49.9826545715332
  end

  @testset "backtest smoke" begin
    M = load_stocks(["AAPL", "GOOG"])
    T = Backtest(M, CrossOverStrategy, 1000)
    run_test(T)
    @test !isempty(RecipesBase.apply_recipe(Dict{Symbol,Any}(), T.broker))
  end
end
