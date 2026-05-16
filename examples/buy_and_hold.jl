using Qt

M = market([AAPL])

function bah_init(s::Strategy)
end

function bah_next(s::Strategy)
    length(s.market) == 1 || return          # only act on day 1
    aapl = s.market["AAPL"]
    placeOrder!(s.broker, Order(Buy(aapl, 10)))
end

@generateStrategy BuyAndHold bah_next bah_init

bt = Backtest(M, BuyAndHold, 10_000)
runTest(bt)

println(bt)
status(bt.broker)
plot(bt)
