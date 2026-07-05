using Orcus

# Order mechanics demo: margin/leverage/liquidation, via the Broker API directly
# (no Strategy/Backtest — these are account mechanics, not a trading strategy).

ohlc(rows...) = hcat(collect.(rows)...)   # each row is (Open,High,Low,Close) for one bar

println("== 1. Margin long: 2x leverage on entry ==")
A = Asset("AAPL", ohlc((100.0,100.0,100.0,100.0), (120.0,120.0,120.0,120.0)),
    ["Open","High","Low","Close"])
M = Market([A]); advance_to!(M,1)
model = RegTMargin(0.5, 0.25, 0.0)   # 50% initial margin -> 2x leverage, 25% maintenance
B = Broker(M, 5000.0; margin_model=model)

O = Order(Buy(A), 100)                # notional = 100*100 = 10_000 -- double the cash on hand
place_order!(B,O); process_orders!(B)
P = first(values(B.portfolio))
println("cash drawn: ", 5000.0 - B.cash, " (half of 10_000 notional)")
println("loan: ", P.loan)
println("equity right after entry: ", B.cash + total_value(B.portfolio) - total_loan(B.portfolio),
    " (unchanged -- entry at fair value creates no equity)")

println("\n== 2. Closing repays the loan out of proceeds ==")
advance_to!(M,2)                      # price 100 -> 120, a 20% move
request_to_close_all!(B); resolve_portfolio!(B)
println("cash after close: ", B.cash, " (proceeds 12_000, minus the 5_000 loan)")
println("P&L: ", B.cash - 5000.0, " on a \$5000 stake -- the 2x leverage doubled the 20% move to 40%")

println("\n== 3. Shorts: unconstrained under NoMargin, gated under RegTMargin ==")
A2 = Asset("TSLA", ohlc(fill((200.0,200.0,200.0,200.0), 2)...), ["Open","High","Low","Close"])
M2 = Market([A2]); advance_to!(M2,1)

B0 = Broker(M2, 1.0)                  # NoMargin default, $1 cash
O0 = Order(Sell(A2), 100)             # notional = -20_000
place_order!(B0,O0); process_orders!(B0)
println("NoMargin, \$1 cash, short 20_000 notional: filled = ", !isempty(B0.history))

B1 = Broker(M2, 1.0; margin_model=model)   # same $1 cash, now under RegTMargin
O1 = Order(Sell(A2), 100)
place_order!(B1,O1); process_orders!(B1)
println("RegTMargin, \$1 cash, same order: filled = ", !isempty(B1.history),
    ", rejected = ", length(B1.rejected))

println("\n== 4. Borrow fee accrues daily on financed/short exposure ==")
A3 = Asset("MSFT", ohlc(fill((100.0,100.0,100.0,100.0), 3)...), ["Open","High","Low","Close"])
M3 = Market([A3]); advance_to!(M3,1)
feemodel = RegTMargin(0.5, 0.25, 0.001)    # 10 bps/bar borrow rate
B3 = Broker(M3, 5000.0; margin_model=feemodel)
O3 = Order(Buy(A3), 100)               # loan = 5000
place_order!(B3,O3); process_orders!(B3)
cash0 = B3.cash
advance_to!(M3,2); process_all!(B3)
advance_to!(M3,3); process_all!(B3)
println("cash after 2 bars of static price: ", B3.cash, " (", cash0, " minus 2 * 5000*0.001)")

println("\n== 5. Liquidation on a maintenance breach ==")
A4 = Asset("GME", ohlc((100.0,100.0,100.0,100.0), (50.0,50.0,50.0,50.0)), ["Open","High","Low","Close"])
M4 = Market([A4]); advance_to!(M4,1)
B4 = Broker(M4, 5000.0; margin_model=model)
O4 = Order(Buy(A4), 100)                # notional 10_000, loan 5000
place_order!(B4,O4); process_orders!(B4)
advance_to!(M4,2); process_all!(B4)     # price halves to 50: equity = 0+5000-5000 = 0 < req(1250)
println("margin calls: ", B4.margin_calls, "  positions left: ", length(B4.portfolio),
    "  cash: ", B4.cash)
