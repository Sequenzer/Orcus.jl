@testset verbose=false "Tables" begin
@testset verbose=false "core" begin
    Random.seed!(1234);
    B = broker(3, 1_000_000)
    A = B.market.data[collect(keys(B.market.data))[2]]

    O1 = Order(Buy(A), 10)
    place_order!(B, O1)
    process_order!(B, O1)                  # opens a position: 1 trade, 1 open position

    O2 = Order(Buy(A), 5)
    place_order!(B, O2)
    process_order!(B, O2)                  # adds to the same position: 2 trades

    push!(B.equity_history, B.cash)
    push!(B.equity_history, B.cash)

    tt = trades_table(B)
    @test Tables.istable(tt)
    @test length(tt) == length(B.history) == 2
    @test tt[1].ticker == A.ticker
    @test tt[1].volume == 10.0
    @test tt[2].volume == 5.0
    @test tt[1].delta_cash == B.history[1].delta_cash

    pt = positions_table(B)
    @test Tables.istable(pt)
    @test length(pt) == length(B.portfolio) == 1
    @test pt[1].ticker == A.ticker
    @test pt[1].net_qty == 15.0

    et = equity_table(B)
    @test Tables.istable(et)
    @test length(et) == length(B.equity_history)
    @test et[1] == (bar=1, equity=B.equity_history[1])

    ct = cashflows_table(B)
    @test Tables.istable(ct)
    @test length(ct) == length(cash_history(B))

    coltable = Tables.columntable(tt)
    @test coltable.volume == [10.0, 5.0]
end

@testset verbose=false "empty broker" begin
    M = Market([asset()])
    B = Broker(M, 1000)
    @test isempty(trades_table(B))
    @test isempty(positions_table(B))
    @test isempty(equity_table(B))
    @test Tables.istable(trades_table(B))
    @test Tables.istable(positions_table(B))
    @test Tables.istable(equity_table(B))
    @test Tables.istable(cashflows_table(B))
end

@testset verbose=false "rejected orders are excluded" begin
    Random.seed!(1234);
    M = Market([asset(), asset()])
    A = M.data[collect(keys(M.data))[1]]
    Bp = Broker(M, 1.0)
    big = Order(Buy(A), 1000)
    place_order!(Bp, big)
    process_orders!(Bp)
    @test length(Bp.rejected) == 1
    @test isempty(trades_table(Bp))
end

@testset verbose=false "multiple distinct positions" begin
    Random.seed!(1234);
    M = Market([asset(), asset()])
    B = Broker(M, 1_000_000)
    A = B.market.data[collect(keys(B.market.data))[1]]

    place_order!(B, Order(Buy(A), 10))
    place_order!(B, Order(Sell(A), 10))
    process_orders!(B)

    pt = positions_table(B)
    @test length(pt) == 2
    @test Set(r.kind for r in pt) == Set([:Buy, :Sell])
end

@testset verbose=false "options carry strike and expiry" begin
    Random.seed!(1234);
    M = Market([asset(), asset()])
    B = Broker(M, 1_000_000)
    A = B.market.data[collect(keys(B.market.data))[1]]
    spot = value(A)

    place_order!(B, Order(LongCall(A, spot), 1))
    place_order!(B, Order(ShortCall(A, spot), 1))
    process_orders!(B)

    pt = positions_table(B)
    long_row  = only(r for r in pt if r.kind == :LongCall)
    short_row = only(r for r in pt if r.kind == :ShortCall)
    @test long_row.strike == spot
    @test long_row.expiry === nothing
    @test short_row.strike == spot
    @test short_row.expiry == 30
end

@testset verbose=false "closed position leaves a trade but no open position" begin
    Random.seed!(1234);
    B = broker(3, 1_000_000)
    A = B.market.data[collect(keys(B.market.data))[2]]

    place_order!(B, Order(Buy(A), 10))
    process_orders!(B)
    request_to_close_all!(B)
    resolve_portfolio!(B)

    @test length(trades_table(B)) == 2      # open + close
    @test isempty(positions_table(B))
end

@testset verbose=false "cashflows_table matches cash_history exactly" begin
    Random.seed!(1234);
    B = broker(3, 1_000_000)
    A = B.market.data[collect(keys(B.market.data))[2]]

    place_order!(B, Order(Buy(A), 10))
    process_orders!(B)
    request_to_close_all!(B)
    resolve_portfolio!(B)

    @test [(r.bar, r.cash) for r in cashflows_table(B)] == cash_history(B)
end
end
