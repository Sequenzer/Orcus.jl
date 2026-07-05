@testset verbose=false "Broker" begin
@testset verbose=false "core" begin
  Random.seed!(1234);
  x=asset();
  y=asset();
  M=Market([x,y]);
  B = Broker(M,1000);
  @test B isa Broker
  @test B.cost_model isa NoCost
  @test isempty(B.rejected)

  B = broker(3,1000);
  isa(B,Broker)
  A = B.market.data[collect(keys(B.market.data))[2]]
  O = Order(Buy(A,10))
  place_order!(B,O)
  @test length(B.orders) == 1
  process_order!(B,O)
  @test length(B.history) == 1
  @test length(B.portfolio) == 1

  P = first(values(B.portfolio))
  request_to_close_all!(B)
  resolve_portfolio!(B)
  @test length(B.history) == 2
  @test length(B.portfolio) == 0
end

@testset verbose=false "fifo+rejection" begin
  Random.seed!(1234);
  M = Market([asset(), asset()]);
  B = Broker(M, 1_000_000);
  A = B.market.data[collect(keys(B.market.data))[1]]

  # FIFO: orders fill front-to-back
  o1 = Order(Buy(A), 1); o2 = Order(Buy(A), 2); o3 = Order(Buy(A), 3)
  place_order!(B, o1); place_order!(B, o2); place_order!(B, o3)
  process_orders!(B)
  @test isempty(B.orders)
  @test [t.volume for t in B.history] == [1.0, 2.0, 3.0]   # deterministic FIFO order
  @test length(B.portfolio) == 1                            # all three netted into one

  # rejection: an order that can't be funded is recorded, not silently dropped
  Bp = Broker(M, 1.0)
  big = Order(Buy(A), 1000)
  place_order!(Bp, big)
  process_orders!(Bp)
  @test isempty(Bp.history)
  @test length(Bp.rejected) == 1
  @test Bp.rejected[1][1] === big
end

@testset verbose=false "limit/stop orders" begin
  # Deterministic 3-bar OHLC asset: bar1 is just a construction reference, bar2 doesn't
  # trigger, bar3 triggers at-limit (non-gap).
  ohlc(rows...) = hcat(collect.(rows)...)  # each row is (Open,High,Low,Close) for one bar

  Random.seed!(1234);

  # --- Limit buy: resting, then fills at the limit price (no gap) ---
  data = ohlc((100.0,102.0,99.0,101.0), (100.0,101.0,99.0,100.0), (96.0,97.0,95.0,96.0))
  A = Asset("T1", data, ["Open","High","Low","Close"])
  M = Market([A]); advance_to!(M,1)
  B = Broker(M, 1_000_000)
  O = limit_order(Buy(A), 10, 95.0)
  place_order!(B,O)

  advance_to!(M,2); process_orders!(B)
  @test length(B.orders) == 1                # bar2 Low=99 > 95 — no trigger
  @test isempty(B.history)

  advance_to!(M,3); process_orders!(B)
  @test isempty(B.orders)                     # bar3 Low=95 <= 95 — triggers
  @test length(B.history) == 1
  @test B.history[1].volume == 10.0
  P = first(values(B.portfolio))
  @test P.avg_cost == 95.0                    # Open=96 > limit → fills at the limit, not the open

  # --- Limit buy: gap-through fills at the better open price ---
  data2 = ohlc((100.0,102.0,99.0,101.0), (90.0,92.0,88.0,90.0))
  A2 = Asset("T2", data2, ["Open","High","Low","Close"])
  M2 = Market([A2]); advance_to!(M2,1)
  B2 = Broker(M2, 1_000_000)
  O2 = limit_order(Buy(A2), 10, 95.0)
  place_order!(B2,O2)
  advance_to!(M2,2); process_orders!(B2)
  @test isempty(B2.orders)
  P2 = first(values(B2.portfolio))
  @test P2.avg_cost == 90.0                   # Open=90 is better than the limit(95) → fill at open

  # --- Stop buy: resting, then fills at the stop price (no gap) ---
  data3 = ohlc((100.0,102.0,99.0,101.0), (100.0,101.0,99.0,100.0), (100.0,106.0,99.0,104.0))
  A3 = Asset("T3", data3, ["Open","High","Low","Close"])
  M3 = Market([A3]); advance_to!(M3,1)
  B3 = Broker(M3, 1_000_000)
  O3 = stop_order(Buy(A3), 10, 105.0)
  place_order!(B3,O3)
  advance_to!(M3,2); process_orders!(B3)
  @test length(B3.orders) == 1                # bar2 High=101 < 105 — no trigger
  advance_to!(M3,3); process_orders!(B3)
  @test isempty(B3.orders)                    # bar3 High=106 >= 105 — triggers
  P3 = first(values(B3.portfolio))
  @test P3.avg_cost == 105.0                  # Open=100 < stop → fills at the stop, not the open

  # --- Sell-side direction: a Sell order's limit triggers on the opposite bar extreme (High) ---
  data4 = ohlc((100.0,102.0,99.0,101.0), (100.0,104.0,99.0,102.0), (106.0,108.0,105.0,107.0))
  A4 = Asset("T4", data4, ["Open","High","Low","Close"])
  M4 = Market([A4]); advance_to!(M4,1)
  B4 = Broker(M4, 1_000_000)
  O4 = limit_order(Sell(A4), 10, 105.0)       # "short if price rises to >= 105"
  place_order!(B4,O4)
  advance_to!(M4,2); process_orders!(B4)
  @test length(B4.orders) == 1                # bar2 High=104 < 105 — no trigger
  advance_to!(M4,3); process_orders!(B4)
  @test isempty(B4.orders)                    # bar3 High=108 >= 105 — triggers
  P4 = first(values(B4.portfolio))
  @test P4.avg_cost == -106.0                 # Open=106 is better (higher) than the limit(105)

  # Options aren't supported for limit/stop — check_trigger has no method for them.
  A5 = asset()
  @test_throws MethodError check_trigger(limit_order(LongCall(A5,10),1,50.0), broker(1,1000), 1)
end

@testset verbose=false "partial fills" begin
  Random.seed!(1234);
  M = Market([asset(), asset()]);
  A = first(M.assets)

  # opt-in: fills the affordable fraction instead of rejecting, leaves the remainder resting
  B = Broker(M, 500.0)
  O = Order(Buy(A), 100; allow_partial=true)
  place_order!(B,O)
  process_orders!(B)
  @test length(B.history) == 1
  @test 0.0 < B.history[1].volume < 100.0
  @test B.cash >= -1e-9                       # ~0, modulo floating-point roundoff
  @test length(B.orders) == 1                 # remainder still resting
  @test remaining(O) == O.volume - B.history[1].volume

  # opt-out (default): identical scenario rejects outright, exactly as before this feature
  Bd = Broker(M, 500.0)
  Od = Order(Buy(A), 100)
  place_order!(Bd,Od)
  process_orders!(Bd)
  @test isempty(Bd.history)
  @test length(Bd.rejected) == 1
  @test isempty(Bd.orders)

  # affordable_quantity: fee-aware sizing under FlatCost
  cm = FlatCost(commission_pct=0.01, slippage_bps=50.0)
  rho = 0.01 + 50.0/1e4
  qty = Orcus.affordable_quantity(cm, 10.0, 100.0, 500.0)
  @test qty * 10.0 * (1+rho) <= 500.0 + 1e-9
  @test qty < 100.0
  @test Orcus.affordable_quantity(cm, 10.0, -100.0, 500.0) == -100.0   # inflow side is never capped
end

@testset verbose=false "margin / leverage / liquidation" begin
  ohlc(rows...) = hcat(collect.(rows)...)  # each row is (Open,High,Low,Close) for one bar

  Random.seed!(1234);

  # --- Margin long: entry draws only initial_pct*notional, records the loan ---
  A = Asset("M1", ohlc((100.0,100.0,100.0,100.0), (120.0,120.0,120.0,120.0)),
    ["Open","High","Low","Close"])
  M = Market([A]); advance_to!(M,1)
  model = RegTMargin(0.5, 0.25, 0.0)
  B = Broker(M, 5000.0; margin_model=model)
  O = Order(Buy(A), 100)                       # notional = 100*100 = 10_000
  place_order!(B,O); process_orders!(B)
  P = first(values(B.portfolio))
  @test P.loan == 5000.0                       # half of 10_000 financed
  @test B.cash == 0.0                          # exactly the 50% own-cash requirement was drawn
  equity = B.cash + total_value(B.portfolio) - total_loan(B.portfolio)
  @test equity == 5000.0                       # entry at fair value neither creates nor destroys equity

  # --- Margin long: closing repays the loan out of proceeds before crediting free cash ---
  advance_to!(M,2)                             # price moves 100 -> 120
  request_to_close_all!(B); resolve_portfolio!(B)
  @test isempty(B.portfolio)
  @test P.loan == 0.0                          # loan fully repaid on close (same Position object)
  @test B.cash == 7000.0                       # proceeds 12_000, less the 5_000 loan repaid
  # $2000 P&L on a $5000 own-cash stake — the 2x leverage doubled the raw 20% price move to 40%
  @test (B.cash - 5000.0) == 2000.0

  # --- Short margin requirement: NoMargin never gates it; RegTMargin does ---
  A2 = asset()
  M2 = Market([A2])
  p2 = price(Sell(A2))
  required = abs(10*p2) * 0.5

  B0 = Broker(M2, 1.0)                         # NoMargin default — unconstrained, as today
  O0 = Order(Sell(A2), 10)
  place_order!(B0,O0); process_orders!(B0)
  @test length(B0.history) == 1

  B1 = Broker(M2, required - 1.0; margin_model=model)   # just short of the requirement
  O1 = Order(Sell(A2), 10)
  place_order!(B1,O1); process_orders!(B1)
  @test isempty(B1.history)
  @test length(B1.rejected) == 1

  B2 = Broker(M2, required + 1.0; margin_model=model)   # clears the requirement
  O2 = Order(Sell(A2), 10)
  place_order!(B2,O2); process_orders!(B2)
  @test length(B2.history) == 1

  # --- Partial fill under margin: long open sized down to the affordable margin fraction ---
  M3 = Market([asset(), asset()])
  A3 = first(M3.assets)
  p3 = price(Buy(A3))
  B3 = Broker(M3, 100*p3*0.5*0.3; margin_model=model)   # ~30% of the margin-adjusted full size
  O3 = Order(Buy(A3), 100; allow_partial=true)
  place_order!(B3,O3); process_orders!(B3)
  @test length(B3.history) == 1
  filled3 = B3.history[1].volume
  @test 0.0 < filled3 < 100.0
  @test B3.cash >= -1e-9
  @test length(B3.orders) == 1                 # remainder stays resting
  P3 = first(values(B3.portfolio))
  @test P3.loan ≈ filled3 * p3 * 0.5

  # --- Partial fill under margin: short open sized down to the affordable skin-in-the-game cash ---
  A4 = asset()
  M4 = Market([A4])
  p4 = price(Sell(A4))
  B4 = Broker(M4, abs(100*p4)*0.5*0.3; margin_model=model)
  O4 = Order(Sell(A4), 100; allow_partial=true)
  place_order!(B4,O4); process_orders!(B4)
  @test length(B4.history) == 1
  filled4 = B4.history[1].volume
  @test 0.0 < filled4 < 100.0
  @test length(B4.orders) == 1

  # --- Borrow fee: charged daily on financed-long exposure, zero under NoMargin ---
  A5 = Asset("M5", ohlc(fill((100.0,100.0,100.0,100.0), 3)...), ["Open","High","Low","Close"])
  M5 = Market([A5]); advance_to!(M5,1)
  feemodel = RegTMargin(0.5, 0.0, 0.001)       # maintenance disabled for this test
  B5 = Broker(M5, 5000.0; margin_model=feemodel)
  O5 = Order(Buy(A5), 100)                     # notional 10_000, loan 5000
  place_order!(B5,O5); process_orders!(B5)
  @test B5.cash == 0.0
  advance_to!(M5,2); process_all!(B5)
  @test B5.cash ≈ -5.0                         # 5000 loan * 0.001
  advance_to!(M5,3); process_all!(B5)
  @test B5.cash ≈ -10.0

  # --- Liquidation: equity breach flattens the whole account ---
  A6 = Asset("M6", ohlc((100.0,100.0,100.0,100.0), (80.0,80.0,80.0,80.0), (50.0,50.0,50.0,50.0)),
    ["Open","High","Low","Close"])
  M6 = Market([A6]); advance_to!(M6,1)
  B6 = Broker(M6, 5000.0; margin_model=model)  # RegTMargin(0.5, 0.25, 0.0)
  O6 = Order(Buy(A6), 100)                     # notional 10_000, loan 5000
  place_order!(B6,O6); process_orders!(B6)

  advance_to!(M6,2); process_all!(B6)          # price 80: equity=0+8000-5000=3000 >= req(2000)
  @test isempty(B6.margin_calls)
  @test length(B6.portfolio) == 1

  advance_to!(M6,3); process_all!(B6)          # price 50: equity=0+5000-5000=0 < req(1250)
  @test length(B6.margin_calls) == 1
  @test isempty(B6.portfolio)
  @test B6.cash ≈ 0.0                          # proceeds 5000, minus the 5000 loan repaid
end

@testset verbose=false "cash conservation" begin
  Random.seed!(1234);
  M = Market([asset(), asset()]);
  cm = FlatCost(commission_pct=0.001, slippage_bps=5.0)
  B  = Broker(M, 1_000_000; cost_model=cm)
  A  = B.market.data[collect(keys(B.market.data))[1]]

  start = B.cash
  O = Order(Buy(A, 10))
  place_order!(B, O); process_orders!(B)
  P = first(values(B.portfolio))
  request_to_close_all!(B); resolve_portfolio!(B)

  # round trip at the same bar: final cash == start minus total fees, and < start
  @test B.cash < start
  total_fees = start - B.cash
  @test total_fees > 0
  @test isempty(B.portfolio)
end
end
