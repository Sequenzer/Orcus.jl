@testset verbose=false "Margin" begin
  @testset "NoMargin — today's behavior" begin
    m = NoMargin()
    @test initial_margin_pct(m) == 1.0
    @test short_margin_rate(m) == 0.0
    @test maintenance_margin_pct(m) == 0.0
    @test borrow_rate(m) == 0.0
  end

  @testset "RegTMargin accessors" begin
    m = RegTMargin(0.5, 0.25, 0.0002)
    @test initial_margin_pct(m) == 0.5
    @test short_margin_rate(m) == 0.5
    @test maintenance_margin_pct(m) == 0.25
    @test borrow_rate(m) == 0.0002
  end
end
