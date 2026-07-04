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
end
end
