using Orcus: apply_trade!, request_to_close

@testset verbose=false "Position" begin
  @testset verbose=false "core" begin
    @testset "construct + flags" begin
      Random.seed!(1234);
      A = asset()
      D = Buy(A, 10)
      P = Position(D)
      @test is_closed(P)                 # fresh position holds nothing
      @test P.net_qty == 0.0
      @test P.requestToClose == false
      request_to_close(P)
      @test P.requestToClose == true
    end

    @testset "open + weighted average" begin
      Random.seed!(1234);
      A = asset()
      D = Buy(A)
      P = Position(D)
      apply_trade!(P, 10.0, 100.0)       # 10 @ 100
      apply_trade!(P, 10.0, 120.0)       # +10 @ 120
      @test P.net_qty == 20.0
      @test P.avg_cost ≈ 110.0           # weighted average entry
      @test !is_closed(P)
    end

    @testset "partial close realizes pnl" begin
      Random.seed!(1234);
      A = asset()
      P = Position(Buy(A))
      apply_trade!(P, 10.0, 100.0)
      apply_trade!(P, -4.0, 130.0)       # sell 4 @ 130 → realize 4*(130-100)
      @test P.net_qty == 6.0
      @test P.realized_pnl ≈ 120.0
      @test P.avg_cost ≈ 100.0           # basis unchanged on a reduce
    end

    @testset "full close removes qty" begin
      Random.seed!(1234);
      A = asset()
      P = Position(Buy(A))
      apply_trade!(P, 10.0, 100.0)
      apply_trade!(P, -10.0, 110.0)
      @test is_closed(P)
      @test P.realized_pnl ≈ 100.0
      @test P.avg_cost == 0.0
    end

    @testset "flip through zero" begin
      Random.seed!(1234);
      A = asset()
      P = Position(Buy(A))
      apply_trade!(P, 10.0, 100.0)
      apply_trade!(P, -15.0, 120.0)      # close 10 (+200), flip to -5 @ 120
      @test P.net_qty == -5.0
      @test P.avg_cost ≈ 120.0           # new lot opens at the fill price
      @test P.realized_pnl ≈ 200.0
    end

    @testset "fees hit realized pnl" begin
      Random.seed!(1234);
      A = asset()
      P = Position(Buy(A))
      apply_trade!(P, 10.0, 100.0, 5.0)  # 5.0 fee on open
      @test P.realized_pnl ≈ -5.0
    end

    @testset "loan (margin financing)" begin
      Random.seed!(1234);
      A = asset()

      # opening with borrowed sets loan; adding accumulates it
      P = Position(Buy(A))
      apply_trade!(P, 10.0, 100.0, 0.0; borrowed=500.0)   # 1000 notional, 500 financed
      @test P.loan == 500.0
      apply_trade!(P, 10.0, 100.0, 0.0; borrowed=500.0)   # add another 1000 notional, 500 financed
      @test P.loan == 1000.0

      # reducing repays proportionally to the fraction closed
      apply_trade!(P, -10.0, 100.0)                       # close half (10 of 20)
      @test P.net_qty == 10.0
      @test P.loan ≈ 500.0

      # full close drives loan to exactly 0.0
      apply_trade!(P, -10.0, 100.0)
      @test is_closed(P)
      @test P.loan == 0.0

      # flip-through-zero also drives loan to exactly 0.0, even without repaying explicitly
      Q = Position(Buy(A))
      apply_trade!(Q, 10.0, 100.0, 0.0; borrowed=400.0)
      apply_trade!(Q, -15.0, 110.0)                        # close 10, flip to -5
      @test Q.net_qty == -5.0
      @test Q.loan == 0.0

      # default borrowed=0.0 — every pre-margin call site is unaffected
      R = Position(Buy(A))
      apply_trade!(R, 10.0, 100.0)
      @test R.loan == 0.0
    end
  end
end
