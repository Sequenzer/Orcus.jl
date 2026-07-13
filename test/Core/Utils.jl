@testset "Utilities" begin
  @testset "DataSeries" begin
    dp1 = Float64[1, 2, NaN, 4, 5]
    dp2 = Float64[1, 2, NaN, 4, NaN, NaN]
    ds = data_series([dp1, fill(NaN, 6), dp2])

    @test ds[1, 1] == 1
    @test isnan(ds[1, 3])
    @test size(ds) == (3, 6)

    ds2 = data_series([dp1, dp2])
    @test size(ds2) == (2, 6)
  end
end

@testset "GBM" begin
  @testset "gbm_step univariate" begin
    @test gbm_step(100.0, 0.0, 0.0) == 100.0
    @test gbm_step(100.0, log(2), 0.0) == 200.0
    @test gbm_step(100.0, -log(2), 0.0) == 50.0

    Random.seed!(1234)
    n = 100_000
    sample = [gbm_step(100.0, 0.0, 0.02) for _ in 1:n]
    se = 100.0 * 0.02 / sqrt(n)
    @test abs(mean(sample) - 100.0) < 5 * se
    @test minimum(sample) > 0
  end

  @testset "gbm_path univariate" begin
    Random.seed!(1234)
    path = gbm_path(100.0, 0.0, 0.02, 500)
    @test path[1] == 100.0
    @test length(path) == 500
    @test minimum(path) > 0

    flat = gbm_path(100.0, log(2) / 10, 0.0, 11)
    @test flat ≈ 100.0 .* exp.((log(2) / 10) .* (0:10))
  end

  @testset "gbm_step/gbm_path multivariate" begin
    rho = [1.0 0.5; 0.5 1.0]
    @test gbm_step([100.0, 200.0], [0.0, 0.0], [0.0, 0.0], rho) == [100.0, 200.0]
    @test gbm_step([100.0, 200.0], [log(2), -log(2)], [0.0, 0.0], rho) == [200.0, 100.0]

    x0 = [100.0, 200.0]
    Random.seed!(1234)
    path = gbm_path(x0, [0.0, 0.0], [0.02, 0.02], rho, 500)
    @test size(path) == (2, 500)
    @test path[:, 1] == x0
    @test minimum(path) > 0

    @test size(gbm_step(x0, [0.0, 0.0], [0.0, 0.0], rho)) == (2,)

    Random.seed!(1234)
    n = 20_000
    corr_path = gbm_path(x0, [0.0, 0.0], [0.02, 0.02], [1.0 0.9; 0.9 1.0], n)
    r1 = diff(log.(corr_path[1, :]))
    r2 = diff(log.(corr_path[2, :]))
    @test cor(r1, r2) ≈ 0.9 atol = 0.05

    Random.seed!(1234)
    indep_path = gbm_path(x0, [0.0, 0.0], [0.02, 0.02], [1.0 0.0; 0.0 1.0], n)
    ri1 = diff(log.(indep_path[1, :]))
    ri2 = diff(log.(indep_path[2, :]))
    @test cor(ri1, ri2) ≈ 0.0 atol = 0.05
  end

  @testset "gbm_path_segments univariate" begin
    segments = [(mu=0.0, sigma=0.0, n=3), (mu=log(2), sigma=0.0, n=2)]
    p = gbm_path_segments(100.0, segments)
    @test p == [100.0, 100.0, 100.0, 200.0]
    @test length(p) == 1 + sum(s.n for s in segments) - length(segments)

    crash_segments = [
      (mu=0.0, sigma=0.0, n=5), (mu=-1.0, sigma=0.0, n=2), (mu=0.0, sigma=0.0, n=5)
    ]
    cp = gbm_path_segments(100.0, crash_segments)
    @test cp[6] < cp[5]           # price right after the crash segment starts dropping
    @test cp[end] == cp[6]        # flat recovery regime holds the post-crash level
  end

  @testset "gbm_path_segments multivariate" begin
    x0 = [100.0, 200.0]
    rho = [1.0 0.5; 0.5 1.0]
    segments = [(mu=[0.0, 0.0], sigma=[0.0, 0.0], rho=rho, n=3),
      (mu=[log(2), -log(2)], sigma=[0.0, 0.0], rho=rho, n=2)]
    p = gbm_path_segments(x0, segments)
    @test size(p) == (2, 1 + sum(s.n for s in segments) - length(segments))
    @test p[1, :] == [100.0, 100.0, 100.0, 200.0]
    @test p[2, :] == [200.0, 200.0, 200.0, 100.0]
  end
end
