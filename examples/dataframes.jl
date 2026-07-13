using Orcus
using DataFrames

M = market([AAPL])
bt = Backtest(M, CrossOverStrategy, 10_000)
run_test(bt)

trades = DataFrame(trades_table(bt.broker))
positions = DataFrame(positions_table(bt.broker))
equity = DataFrame(equity_table(bt.broker))
cashflows = DataFrame(cashflows_table(bt.broker))

println(first(trades, 5))
println(describe(trades))
println(combine(groupby(trades, :ticker), :volume => sum => :total_volume))
