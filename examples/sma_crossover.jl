using Orcus
using Plots
unicodeplots()

M = market([GOOG])

function cross_init(s::Strategy)
    for (_, a) in s.market.data
        apply_indicator(IndicatorGenerator(simple_average, 10), a, "Close", "SMA10")
        apply_indicator(IndicatorGenerator(simple_average, 20), a, "Close", "SMA20")
    end
end

function cross_next(s::Strategy)
    for (_, a) in s.market.data
        n = length(a)
        n < 2 && continue
        isnan(a["SMA10", n])   && continue
        isnan(a["SMA20", n])   && continue
        isnan(a["SMA10", n-1]) && continue
        isnan(a["SMA20", n-1]) && continue

        crossed_up   = a["SMA10", n] >  a["SMA20", n] && a["SMA10", n-1] <= a["SMA20", n-1]
        crossed_down = a["SMA10", n] <  a["SMA20", n] && a["SMA10", n-1] >= a["SMA20", n-1]

        if crossed_up
            requestToCloseAll!(s.broker)
            placeOrder!(s.broker, Order(Buy(a, 5)))
        elseif crossed_down
            requestToCloseAll!(s.broker)   # go flat, no short
        end
    end
end

@generateStrategy SMAcrossover cross_next cross_init

bt = Backtest(M, SMAcrossover, 10_000)
runTest(bt)

println(bt)
status(bt.broker)
plot(bt)
