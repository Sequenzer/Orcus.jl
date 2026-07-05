using Orcus

# Order mechanics demo: limit/stop orders and partial fills, via the Broker API directly
# (no Strategy/Backtest — these are order-book mechanics, not a trading strategy).

ohlc(rows...) = hcat(collect.(rows)...)   # each row is (Open,High,Low,Close) for one bar

println("== 1. Limit order: resting until price dips, then fills at the limit ==")
A = Asset("AAPL",
  ohlc((100.0, 102.0, 99.0, 101.0), (100.0, 101.0, 99.0, 100.0), (96.0, 97.0, 95.0, 96.0)),
  ["Open", "High", "Low", "Close"])
M = Market([A]);
advance_to!(M, 1)
B = Broker(M, 100_000)

O = limit_order(Buy(A), 10, 95.0)     # "buy 10 if price drops to 95"
place_order!(B, O)

advance_to!(M, 2);
process_orders!(B)
println("bar2 (Low=99): still resting? ", !isfulfilled(O), "  in book: ", length(B.orders))

advance_to!(M, 3);
process_orders!(B)
println(
  "bar3 (Low=95): filled? ",
  isfulfilled(O),
  "  fill price: ",
  first(values(B.portfolio)).avg_cost,
)

println("\n== 2. Stop order: breakout entry ==")
A2 = Asset("TSLA",
  ohlc(
    (100.0, 102.0, 99.0, 101.0), (100.0, 101.0, 99.0, 100.0), (100.0, 106.0, 99.0, 104.0)
  ),
  ["Open", "High", "Low", "Close"])
M2 = Market([A2]);
advance_to!(M2, 1)
B2 = Broker(M2, 100_000)
O2 = stop_order(Buy(A2), 10, 105.0)   # "buy 10 if price breaks out above 105"
place_order!(B2, O2)
advance_to!(M2, 2);
process_orders!(B2)
println("bar2 (High=101): triggered? ", isfulfilled(O2))
advance_to!(M2, 3);
process_orders!(B2)
println(
  "bar3 (High=106): triggered? ",
  isfulfilled(O2),
  "  fill price: ",
  first(values(B2.portfolio)).avg_cost,
)

println("\n== 3. Gap-through: fill at the better open, not the stated price ==")
A3 = Asset(
  "NFLX",
  ohlc((100.0, 102.0, 99.0, 101.0), (90.0, 92.0, 88.0, 90.0)),
  ["Open", "High", "Low", "Close"],
)
M3 = Market([A3]);
advance_to!(M3, 1)
B3 = Broker(M3, 100_000)
O3 = limit_order(Buy(A3), 10, 95.0)   # opens well below the limit -- gaps through
place_order!(B3, O3)
advance_to!(M3, 2);
process_orders!(B3)
println(
  "limit was 95, open gapped to 90 -> filled at: ", first(values(B3.portfolio)).avg_cost
)

println("\n== 4. Partial fill: not enough cash for the whole order ==")
M4 = Market([asset()])
A4 = first(M4.assets)
B4 = Broker(M4, 500.0)
p = price(Buy(A4))
println(
  "unit price ~",
  round(p, digits=2),
  " -> 100 units would cost ~",
  round(100p, digits=2),
  ", cash is 500",
)
O4 = Order(Buy(A4), 100; allow_partial=true)   # opt-in
place_order!(B4, O4)
process_orders!(B4)
println(
  "filled this bar: ", B4.history[1].volume, " units, cash left: ", round(B4.cash, digits=4)
)
println(
  "still resting: ", remaining(O4), " units, order still in book? ", !isempty(B4.orders)
)

println("\n== 5. Same scenario WITHOUT allow_partial: rejected outright ==")
B5 = Broker(M4, 500.0)
O5 = Order(Buy(A4), 100)   # default: allow_partial=false
place_order!(B5, O5)
process_orders!(B5)
println("history: ", length(B5.history), "  rejected: ", length(B5.rejected))
