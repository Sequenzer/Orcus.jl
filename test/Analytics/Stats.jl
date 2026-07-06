@testset verbose = false "Analytics.Stats" begin
  @testset "infer_periods_per_year" begin
    daily = DateTime.(Date(2020, 1, 1):Day(1):Date(2020, 12, 31))
    @test infer_periods_per_year(daily) == 252
    weekly = DateTime.(Date(2020, 1, 1):Week(1):Date(2021, 12, 31))
    @test infer_periods_per_year(weekly) == 52
    monthly = DateTime.(Date(2015, 1, 1):Month(1):Date(2020, 1, 1))
    @test infer_periods_per_year(monthly) == 12
    yearly = DateTime.(Date(2000, 1, 1):Year(1):Date(2020, 1, 1))
    @test infer_periods_per_year(yearly) == 1
    hourly = collect(DateTime(2020, 1, 1):Hour(1):DateTime(2020, 1, 10))
    @test infer_periods_per_year(hourly) == 252 * 24
    @test infer_periods_per_year(daily[1:1]) == 252

    A = Asset("X", [1.0 2.0; 1.0 2.0], ["Open", "Close"])
    M = market([A])
    @test infer_periods_per_year(M) == 252
    set_axis!(M, [DateTime(2020, 1, 1), DateTime(2020, 1, 8)])
    @test infer_periods_per_year(M) == 52
  end
end
