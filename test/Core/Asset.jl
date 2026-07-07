@testset verbose=false "Asset" begin
  @testset verbose=false "core" begin
    @testset "constructor" begin
      dp1 = Float64[1, 2, NaN, 4, 5]
      dp2 = Float64[1, 2, NaN, 4, NaN, NaN]
      ds = data_series([dp1, fill(NaN, 6), dp2])

      @test isa(asset("AAPL", ds, ["1", "2", "3"]), Asset)
    end
    @testset "constant" begin
      ticker = "TSTS"
      i = 1:1:100
      A = asset(ticker, i, 0.0, 0.0, 100, 10)   # mu=0, sigma=0 -> exact martingale, no noise
      @test A["Close"] == fill(100, 100)
      @test length(A) == 100
    end
    @testset "geometric growth" begin
      ticker = "TSTS"
      i = 1:1:100
      mu = log(2) / 100   # deterministic drift: Close[100] == 100 * 2^1 == 200
      A = asset(ticker, i, mu, 0.0, 100, 2)
      @test A["Close"] ≈ 100 .* 2 .^ (i ./ 100)
      @test A["High"] == A["Close"]              # growing bar: high == close
      @test A["Low"][1] == 100
      @test issorted(A["Close"])
      @test length(A) == 100
      @test value(A) ≈ A["Close"][end]
      @test value(A) ≈ 200
    end
    @testset "name indexing is concrete and throws on absent keys" begin
      A = asset("TSTS", 1:1:100, 0.0, 0.0, 100, 10)
      @test_throws KeyError A["NOPE"]
      @test_throws KeyError A["NOPE", 1]
      @test @inferred(A["Close"]) isa Vector{Float64}
      @test @inferred(A["Close", 1]) isa Float64
    end
    @testset "geometric decay" begin
      ticker = "TSTS"
      i = 1:1:100
      mu = -log(2) / 100   # deterministic drift: Close[100] == 100 * 2^-1 == 50
      A = asset(ticker, i, mu, 0.0, 100, 2)
      @test A["Close"] ≈ 100 .* 2 .^ (-i ./ 100)
      @test A["Low"] == A["Close"]               # shrinking bar: low == close
      @test A["High"][1] == 100
      @test issorted(A["Close"]; rev=true)
      @test length(A) == 100
    end

    @testset "add_datapoint!" begin
      ticker = "TSTS"
      i = 1:1:100
      A = asset(ticker, i, 0.0, 0.0, 100, 2)
      SMA20=IndicatorGenerator(simple_average, 20)
      apply_indicator(SMA20, A, "Close", "SMA20")
      add_datapoint!(A, Float64[113, 113, 113, 113, NaN])
      add_datapoint!(A, Float64[113, 113, 113, 113, NaN])
      @test A.data[5, end] == 100.65
      @test A.data[4, end] == 113
    end
  end
end
