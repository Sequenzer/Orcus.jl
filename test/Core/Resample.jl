@testset verbose = false "Resample" begin
  @testset "OHLCV rules with NaN gaps" begin
    O = [1.0, NaN, 3.0, 4.0, 5.0, 6.0, 7.0]
    H = [10.0, 12.0, 11.0, NaN, 13.0, 12.0, 14.0]
    L = [0.5, 0.4, NaN, 0.3, 0.6, 0.2, 0.7]
    C = [1.5, 2.5, NaN, 4.5, 5.5, 6.5, 7.5]
    V = [100.0, NaN, 50.0, 25.0, NaN, 10.0, 5.0]
    data = permutedims(hcat(O, H, L, C, V))
    A = Asset("R", data, ["Open", "High", "Low", "Close", "Volume"])
    M = market([A])
    ax = DateTime.(Date(2022, 3, 1):Day(1):Date(2022, 3, 7))
    set_axis!(M, ax)

    R = resample(M, 3)                       # stops [3, 6, 7], remainder window of 1
    a = R["R"]
    @test size(a.data, 2) == 3
    @test a["Open", 1] == 1.0
    @test a["Open", 2] == 4.0
    @test a["Open", 3] == 7.0
    @test a["High", 1] == 12.0
    @test a["High", 2] == 13.0
    @test a["Low", 1] == 0.4
    @test a["Low", 2] == 0.2
    @test a["Close", 1] == 2.5
    @test a["Close", 2] == 6.5
    @test a["Close", 3] == 7.5
    @test a["Volume", 1] == 150.0
    @test a["Volume", 2] == 35.0
    @test a["Volume", 3] == 5.0
    @test R.axis == ax[[3, 6, 7]]

    # purity: source untouched, output owns its data
    @test isequal(M["R"].data, data)
    @test R["R"].data !== M["R"].data
  end

  @testset "all-NaN windows and non-OHLC rows" begin
    C = [NaN, NaN, NaN, 1.0]
    V = [NaN, NaN, NaN, 2.0]
    X = [7.0, 8.0, NaN, NaN]
    A = Asset("N", permutedims(hcat(C, V, X)), ["Close", "Volume", "Custom"])
    R = resample(market([A]), 3)
    a = R["N"]
    @test isnan(a["Close", 1])
    @test isnan(a["Volume", 1])              # NaN, not 0.0
    @test a["Close", 2] == 1.0
    @test a["Volume", 2] == 2.0
    @test a["Custom", 1] == 8.0              # last non-NaN
    @test isnan(a["Custom", 2])
  end

  @testset "period grouping" begin
    ax = DateTime.(Date(2022, 1, 15):Day(1):Date(2022, 3, 10))
    n = length(ax)
    A = Asset("P", permutedims(hcat(collect(1.0:n))), ["Close"])
    M = market([A])
    set_axis!(M, ax)
    R = resample(M, Month(1))
    @test size(R["P"].data, 2) == 3          # Jan, Feb, Mar
    @test R.axis == [DateTime(2022, 1, 31), DateTime(2022, 2, 28), DateTime(2022, 3, 10)]
    @test R["P"]["Close", 1] == 17.0         # Jan 15..31 → last bar
    @test R["P"]["Close", 3] == Float64(n)

    @test_throws Exception resample(market([copy(A)]), Week(1))   # no axis
    @test_throws Exception resample(M, 0)
  end

  @testset "indicator generators reset" begin
    Random.seed!(1234)
    A = asset()
    SMA20 = IndicatorGenerator(simple_average, 20)
    apply_indicator(SMA20, A, "Close", "SMA20")
    R = resample(market([A]), 5)
    @test all(isnothing, R[A.ticker].indicator_functions)
    @test "SMA20" in names(R[A.ticker])      # materialized row survives as data
  end

  @testset "sample data round trip" begin
    M = load_stocks(["AAPL"])
    R = resample(M, Week(1))
    @test has_axis(R)
    @test length(R.axis) < length(M.axis)
    @test issorted(R.axis)
    @test size(R["AAPL"].data, 2) == length(R.axis)
  end
end
