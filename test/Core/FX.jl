@testset verbose = false "FX" begin
  function _flat_bars(p::Vector{Float64})
    permutedims(hcat(p, p, p, p))
  end
  OHLC = ["Open", "High", "Low", "Close"]
  prices = [10.0, 12.0, 11.0, 13.0]

  function _run(; currency::Symbol=:base, rates::Union{Nothing,Vector{Float64}}=nothing,
    cash::Float64=1000.0, qty::Int=10)
    A = Asset("X", _flat_bars(prices), OHLC; currency=currency)
    M = market([A])
    rates === nothing || set_fx!(M, currency, Asset("FXR", _flat_bars(rates), OHLC))
    advance_to!(M, 1)
    B = Broker(M, cash)
    place_order!(B, Order(Buy(A), qty))
    process_orders!(B)
    push!(B.equity_history, B.cash + total_value(B.portfolio))
    advance_to!(M, 2)
    process_all!(B)
    advance_to!(M, 3)
    process_all!(B)
    request_to_close_all!(B)
    resolve_portfolio!(B)
    advance_to!(M, 4)
    process_all!(B)
    return M, B
  end

  @testset "flat rate 2.0 scales the whole book by 2" begin
    _, Bl = _run()
    _, Bf = _run(; currency=:EUR, rates=fill(2.0, 4), cash=2000.0)
    @test Bf.cash == 2 * Bl.cash
    @test Bf.equity_history == 2 .* Bl.equity_history
    @test [T.delta_cash for T in Bf.history] == 2 .* [T.delta_cash for T in Bl.history]
  end

  @testset "time-varying rate: base-book accounting" begin
    rates = [1.0, 1.5, 2.0, 2.5]
    M, B = _run(; currency=:EUR, rates=rates, cash=1000.0, qty=1)
    # fill at bar 1: 10 * 1.0 base out; close at bar 3: 11 * 2.0 base in
    @test B.history[1].delta_cash == -10.0
    @test B.history[2].delta_cash == 22.0
    @test B.cash == 1000.0 - 10.0 + 22.0
    # bar-2 mark includes the fx move: 12 * 1.5 = 18
    @test B.equity_history[2] == 990.0 + 18.0
  end

  @testset "no lookahead: rate respects the visible cursor" begin
    rates = [1.0, 1.5, 2.0, 2.5]
    A = Asset("X", _flat_bars(prices), OHLC; currency=:EUR)
    M = market([A])
    set_fx!(M, :EUR, Asset("FXR", _flat_bars(rates), OHLC))
    advance_to!(M, 2)
    @test value(M["FXR"]) == 1.5
    @test Orcus._fx_convert(A, 12.0) == 12.0 * 1.5
    advance_to!(M, 3)
    @test Orcus._fx_convert(A, 12.0) == 12.0 * 2.0
  end

  @testset "set_fx! wiring order" begin
    FXR = Asset("FXR", _flat_bars([2.0, 2.0, 2.0, 2.0]), OHLC)
    A1 = Asset("BEFORE", _flat_bars(prices), OHLC; currency=:EUR)
    M = market([A1])
    set_fx!(M, :EUR, FXR)
    @test A1.fx === M["FXR"]
    A2 = Asset("AFTER", _flat_bars(prices), OHLC; currency=:EUR)
    add_asset!(M, A2)
    @test A2.fx === M["FXR"]
    base_asset = Asset("BASE", _flat_bars(prices), OHLC)
    add_asset!(M, base_asset)
    @test base_asset.fx === nothing
  end

  @testset "copy(Market) rewires fx references" begin
    A = Asset("X", _flat_bars(prices), OHLC; currency=:EUR)
    M = market([A])
    set_fx!(M, :EUR, Asset("FXR", _flat_bars([2.0, 2.0, 2.0, 2.0]), OHLC))
    C = copy(M)
    @test C["X"].fx === C["FXR"]
    @test C["X"].fx !== M["FXR"]
    S = M[1:2]
    @test S["X"].fx === S["FXR"]
    R = resample(M, 2)
    @test R["X"].fx === R["FXR"]
    T = trim_to_length(M, 2)
    @test T["X"].fx === T["FXR"]
  end

  @testset "threaded batch on multi-currency market" begin
    global fx_batch_init(_::Strategy) = nothing
    global function fx_batch_next(s::Strategy)
      length(s.market) == 1 || return nothing
      place_order!(s.broker, Order(Buy(s.market["X"], s.qty)))
    end
    @generate_strategy FXBatchSmoke fx_batch_next fx_batch_init qty::Int=1

    A = Asset("X", _flat_bars(prices), OHLC; currency=:EUR)
    M = market([A])
    set_fx!(M, :EUR, Asset("FXR", _flat_bars([1.0, 1.5, 2.0, 2.5]), OHLC))
    grid = [(qty=1,), (qty=2,), (qty=3,)]
    seq = batch_backtest(M, FXBatchSmoke, 1000, grid; threaded=false)
    par = batch_backtest(M, FXBatchSmoke, 1000, grid; threaded=true)
    @test [b.broker.cash for b in par] == [b.broker.cash for b in seq]
    @test [b.broker.equity_history for b in par] == [b.broker.equity_history for b in seq]
  end

  @testset "tables report base currency" begin
    rates = [1.0, 1.5, 2.0, 2.5]
    M, B = _run(; currency=:EUR, rates=rates, cash=1000.0, qty=1)
    tt = trades_table(B)
    # entry trade: derivative's stored price (local 10.0) at the bar-1 rate
    @test tt[1].price == 10.0 * rates[1]
    wt = weights_table(B)
    r2 = only(filter(r -> r.bar == 2, wt))
    @test r2.value == 12.0 * 1.5
  end
end
