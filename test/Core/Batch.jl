@testset verbose=false "Batch" begin

    # param-carrying strategy; `init` mutates each asset (attaches an indicator), so a
    # successful sweep proves per-job isolation (the source asset must stay untouched).
    global function batch_smoke_init(s::Strategy)
        for (_, a) in s.market.data
            apply_indicator(IndicatorGenerator(simple_average, 5), a, "Close", "SMA5")
        end
    end
    global function batch_smoke_next(s::Strategy)
        length(s.market) == 1 || return            # buy once, on the first bar
        for (_, a) in s.market.data
            placeOrder!(s.broker, Order(Buy(a, s.qty)))
        end
    end
    @generateStrategy BatchSmoke batch_smoke_next batch_smoke_init qty::Int=1

    Random.seed!(1234)
    base       = Market([asset("BCH")])
    rows_before = size(base["BCH"].data, 1)
    grid       = [(qty=1,), (qty=5,), (qty=10,)]

    @testset "grid form: shape, order, isolation" begin
        seq = batch_backtest(base, BatchSmoke, 100_000, grid; threaded=false)
        par = batch_backtest(base, BatchSmoke, 100_000, grid; threaded=true)

        @test seq isa Vector{<:Backtest}
        @test length(seq) == length(grid)
        @test all(b -> b.completed, seq)

        # determinism: threaded result == sequential result, per job, in order
        @test [b.broker.cash for b in par] == [b.broker.cash for b in seq]
        @test [b.broker.equity_history for b in par] == [b.broker.equity_history for b in seq]

        # params actually reach the strategy → distinct outcomes
        @test length(unique(b.broker.cash for b in seq)) == length(grid)

        # source market/asset untouched despite `init` attaching an indicator in each job
        @test size(base["BCH"].data, 1) == rows_before
    end

    @testset "builder form" begin
        n = 3
        res = batch_backtest(n; threaded=false) do i
            M = Market([copy(base["BCH"])])
            runTest(Backtest(M, BatchSmoke, 100_000; params=(qty=i,)))
        end
        @test length(res) == n
        @test all(b -> b.completed, res)
        @test length(unique(b.broker.cash for b in res)) == n
    end

    @testset "back-compat: zero-field @generateStrategy" begin
        global bc_init(_::Strategy) = nothing
        global bc_next(_::Strategy) = nothing
        @generateStrategy BatchNoParam bc_next bc_init
        bt = Backtest(Market([asset("ZZZ")]), BatchNoParam, 1000)   # 1-arg constructor still valid
        runTest(bt)
        @test bt.completed
    end
end
