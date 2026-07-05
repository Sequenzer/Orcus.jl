@testset verbose=false "Cost" begin
  @testset "NoCost" begin
    c = transaction_cost(NoCost(), 12_345.6)
    @test c.commission == 0.0
    @test c.slippage == 0.0
    c2 = transaction_cost(NoCost(), -9_999.0)
    @test c2.commission == 0.0
    @test c2.slippage == 0.0
  end

  @testset "FlatCost math" begin
    cm = FlatCost(commission_pct=0.001, slippage_bps=5.0)
    c = transaction_cost(cm, 10_000.0)
    @test c.commission ≈ 10.0          # 0.1% of 10_000
    @test c.slippage ≈ 5.0           # 5 bps of 10_000

    # both directions charge the same (uses |notional|)
    cn = transaction_cost(cm, -10_000.0)
    @test cn.commission ≈ 10.0
    @test cn.slippage ≈ 5.0
  end

  @testset "FlatCost keyword defaults" begin
    cm = FlatCost()
    c = transaction_cost(cm, 50_000.0)
    @test c.commission == 0.0
    @test c.slippage == 0.0
  end
end
