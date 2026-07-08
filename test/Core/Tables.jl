using Orcus: process_order!

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
    long_row = only(r for r in pt if r.kind == :LongCall)
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

  @testset verbose=false "turnover_table and weights_table basic" begin
    Random.seed!(1234)
    M = Market([asset()])
    A = first(values(M.data))
    B = Broker(M, 1_000_000)

    advance_to!(M, 1)
    place_order!(B, Order(Buy(A), 10))
    process_orders!(B)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    advance_to!(M, 2)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    advance_to!(M, 3)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    tot = turnover_table(B)
    @test Tables.istable(tot)
    @test length(tot) == 3
    @test tot[1].traded_notional == abs(B.history[1].delta_cash)
    @test tot[2].traded_notional == 0.0
    @test tot[2].turnover == 0.0
    @test tot[1].turnover == tot[1].traded_notional / B.equity_history[1]

    wt = weights_table(B)
    @test Tables.istable(wt)
    rows_bar1 = [r for r in wt if r.bar == 1]
    @test length(rows_bar1) == 1
    @test rows_bar1[1].ticker == A.ticker
    @test rows_bar1[1].value ≈ 10.0 * A.data[A.close_idx, 1]
    @test rows_bar1[1].weight ≈ rows_bar1[1].value / B.equity_history[1]

    # asset() is sparse (data every 5th bar); bar 3 has no fresh Close, so the value should
    # carry forward the last observed price (bar 1) rather than read a NaN.
    rows_bar3 = [r for r in wt if r.bar == 3]
    @test rows_bar3[1].value ≈ 10.0 * A.data[A.close_idx, 1]
  end

  @testset verbose=false "turnover_table and weights_table across a forced close" begin
    Random.seed!(1234)
    M = Market([asset()])
    A = first(values(M.data))
    B = Broker(M, 1_000_000)

    advance_to!(M, 1)
    place_order!(B, Order(Buy(A), 10))
    process_orders!(B)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    advance_to!(M, 2)
    request_to_close_all!(B)
    resolve_portfolio!(B)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    advance_to!(M, 3)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    @test B.history[2].volume == 0.0    # close-out sentinel

    tot = turnover_table(B)
    @test tot[2].traded_notional == abs(B.history[2].delta_cash)
    @test tot[2].traded_notional > 0.0   # counted via delta_cash, not silently 0 via volume

    wt = weights_table(B)
    @test isempty([r for r in wt if r.bar == 2])
    @test isempty([r for r in wt if r.bar == 3])
  end

  @testset verbose=false "weights_table matches live portfolio at final bar" begin
    Random.seed!(1234)
    M = Market([asset()])
    A = first(values(M.data))
    B = Broker(M, 1_000_000)

    for i in 1:3
      advance_to!(M, i)
      if i == 1
        place_order!(B, Order(Buy(A), 10))
        process_orders!(B)
      end
      push!(B.equity_history, B.cash + total_value(B.portfolio))
    end

    wt = weights_table(B)
    final_bar = length(B.equity_history)
    row = only(r for r in wt if r.bar == final_bar)
    @test row.value ≈ total_value(B.portfolio)
  end

  @testset verbose=false "turnover_table and weights_table on empty broker" begin
    M = Market([asset()])
    B = Broker(M, 1000)
    @test isempty(turnover_table(B))
    @test isempty(weights_table(B))
    @test Tables.istable(turnover_table(B))
    @test Tables.istable(weights_table(B))
  end

  @testset verbose=false "weights_table separates multiple tickers" begin
    Random.seed!(1234)
    M = Market([asset(), asset()])
    tickers = collect(keys(M.data))
    A1 = M.data[tickers[1]]
    A2 = M.data[tickers[2]]
    B = Broker(M, 1_000_000)

    advance_to!(M, 1)
    place_order!(B, Order(Buy(A1), 10))
    place_order!(B, Order(Sell(A2), 5))
    process_orders!(B)
    push!(B.equity_history, B.cash + total_value(B.portfolio))

    wt = weights_table(B)
    @test length(wt) == 2
    @test Set(r.ticker for r in wt) == Set([A1.ticker, A2.ticker])
  end

  @testset verbose=false "timestamp column with axis" begin
    data = [1.0 2.0 3.0; 3.0 4.0 5.0; 0.5 1.5 2.5; 2.0 3.0 4.0]
    A = Asset("TS", data, ["Open", "High", "Low", "Close"])
    M = market([A])
    B = Broker(M, 1000.0)
    O = Order(Buy(A), 1)
    place_order!(B, O)
    process_order!(B, O)
    for _ in 1:3
      push!(B.equity_history, B.cash + total_value(B.portfolio))
    end

    # no axis: row types byte-identical to today
    @test fieldnames(eltype(trades_table(B))) ==
      (:bar, :ticker, :kind, :strike, :expiry, :volume, :price, :delta_cash)
    @test fieldnames(eltype(equity_table(B))) == (:bar, :equity)

    ax = DateTime.(Date(2021, 1, 1):Day(1):Date(2021, 1, 3))
    set_axis!(M, ax)
    @test all(r.timestamp == ax[r.bar] for r in trades_table(B))
    @test all(r.timestamp == ax[r.bar] for r in equity_table(B))
    @test all(r.timestamp == ax[r.bar] for r in cashflows_table(B))
    @test all(r.timestamp == ax[r.bar] for r in turnover_table(B))
    @test all(r.timestamp == ax[r.bar] for r in weights_table(B))
    @test !isempty(trades_table(B)) && !isempty(weights_table(B))
  end
end
