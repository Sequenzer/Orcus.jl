# Regression guards for the 0 B/bar invariant and hot-path inference.
# Probes live in top-level functions and are warmed before measuring, mirroring
# bench/profile_orcus.jl.

_alloc_bars(n) = repeat([100.0, 101.0, 99.0, 100.0], 1, n)   # constant OHLC bars

function _alloc_nomargin_broker(n_assets::Int)
  assets = [
    Asset("AL$i", _alloc_bars(200), ["Open", "High", "Low", "Close"]) for i in 1:n_assets
  ]
  M = Market(assets)
  advance_to!(M, 1)
  B = Broker(M, 1_000_000.0)
  sizehint!(B.equity_history, 256)
  for A in assets
    place_order!(B, Order(Buy(A), 10))
  end
  process_orders!(B)
  advance_to!(M, 2);
  process_all!(B)
  advance_to!(M, 3);
  process_all!(B)
  return M, B
end

function _alloc_fx_broker()
  A = Asset("EA", _alloc_bars(200), ["Open", "High", "Low", "Close"]; currency=:EUR)
  FX = Asset("EURUSD", repeat([2.0, 2.0, 2.0, 2.0], 1, 200), ["Open", "High", "Low", "Close"])
  M = Market([A])
  set_fx!(M, :EUR, FX)
  advance_to!(M, 1)
  B = Broker(M, 1_000_000.0)
  sizehint!(B.equity_history, 256)
  place_order!(B, Order(Buy(A), 10))
  process_orders!(B)
  advance_to!(M, 2);
  process_all!(B)
  advance_to!(M, 3);
  process_all!(B)
  return M, B
end

function _alloc_margin_broker()
  A = Asset("ML", _alloc_bars(200), ["Open", "High", "Low", "Close"])
  M = Market([A])
  advance_to!(M, 1)
  B = Broker(M, 1_000_000.0; margin_model=RegTMargin(0.5, 0.1, 0.0001))
  sizehint!(B.equity_history, 256)
  place_order!(B, Order(Buy(A), 100))
  process_orders!(B)
  advance_to!(M, 2);
  process_all!(B)
  advance_to!(M, 3);
  process_all!(B)
  return M, B
end

@testset verbose = false "Allocations" begin
  @testset "0 B/bar — NoMargin" begin
    for n in (1, 10)
      M, B = _alloc_nomargin_broker(n)
      advance_to!(M, 4)
      @test (@allocated process_all!(B)) == 0
      @test (@allocated advance_to!(M, 5)) == 0
      @test (@allocated Orcus.process_orders!(B)) == 0
      @test (@allocated Orcus.resolve_portfolio!(B)) == 0
      @test (@allocated total_value(B.portfolio)) == 0
      @test (@allocated total_loan(B.portfolio)) == 0
    end
  end

  @testset "0 B/bar — fx-wired asset" begin
    M, B = _alloc_fx_broker()
    advance_to!(M, 4)
    @test (@allocated process_all!(B)) == 0
    @test (@allocated total_value(B.portfolio)) == 0
    @test length(B.portfolio) == 1
  end

  @testset "0 B/bar — RegTMargin with open positions" begin
    M, B = _alloc_margin_broker()
    advance_to!(M, 4)
    @test (@allocated process_all!(B)) == 0
    @test (@allocated Orcus.accrue_borrow_fee!(B)) == 0
    @test (@allocated Orcus.check_margin!(B)) == 0
    @test length(B.portfolio) == 1   # probes above must not have liquidated the book
  end

  @testset "0 B — strategy-facing helpers" begin
    _, B = _alloc_margin_broker()
    has_position(B, "ML");
    position_direction(B, "ML")
    @test (@allocated has_position(B, "ML")) == 0
    @test (@allocated position_direction(B, "ML")) == 0
    @test has_position(B, "ML")
    @test position_direction(B, "ML") === :long
  end

  @testset "0 B — next(strategy)" begin
    A = Asset("NX", _alloc_bars(100), ["Open", "High", "Low", "Close"])
    M = Market([A])
    T = Backtest(M, CrossOverStrategy, 1_000.0)
    run_test(T)   # warms next across every bar; flat bars → no crossovers, no orders
    @test (@allocated Orcus.next(T.strategy)) == 0
  end
end

@testset verbose = false "Inference" begin
  M, B = _alloc_nomargin_broker(1)
  pf = B.portfolio
  A = M.assets[1]
  @test @inferred(total_value(pf)) isa Float64
  @test @inferred(total_loan(pf)) isa Float64
  @test @inferred(Orcus.total_abs_value(pf)) isa Float64
  @test @inferred(Orcus.accrue_fees!(pf, 0.0)) isa Float64
  @test @inferred(value(Position(Buy(A)))) isa Float64
  let (Mfx, Bfx) = _alloc_fx_broker()
    Pfx = first(values(Bfx.portfolio))
    @test @inferred(value(Pfx)) isa Float64
    @test @inferred(total_value(Bfx.portfolio)) isa Float64
  end
  @test @inferred(Orcus.transaction_fee(NoCost(), 1.0)) isa Float64
  @test @inferred(A[1, 1]) isa Float64
  @test @inferred(advance_to!(M, 4)) isa Market
end
