using Orcus
using Plots
unicodeplots()

M = market([AAPL])

function bah_init(s::Strategy)
end

function bah_next(s::Strategy)
  length(s.market) == 1 || return nothing          # only act on day 1
  aapl = s.market["AAPL"]
  place_order!(s.broker, Order(Buy(aapl, 10)))
end

@generate_strategy BuyAndHold bah_next bah_init

bt = Backtest(M, BuyAndHold, 10_000)
run_test(bt)

println(bt)
status(bt.broker)
plot(bt)
