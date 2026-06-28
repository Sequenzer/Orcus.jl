using Orcus
using Printf

function bench(f, label; n=5)
    f()  # warmup
    t = minimum(@elapsed(f()) for _ in 1:n)
    @printf "  %-44s %8.3f ms\n" label t * 1000
end

# ── universe ──────────────────────────────────────────────────────────────────
TICKERS = ["KO", "MO", "DIS", "MRO", "HAL", "BA", "GE", "HON", "AXP", "USB"]
raw = load_stocks(TICKERS)
n   = minimum(length(raw.data[t]) for t in asset_names(raw))
M   = trim_to_length(raw, n)
println("Universe: $(length(M.data)) assets × $n bars\n")

# ── 1. set_data_to! ───────────────────────────────────────────────────────────
println("=== set_data_to! ===")
base = copy(M)
work = copy(M)
bench("mid-history (1:$(n÷2))") do
    set_data_to!(work, base, 1:(n ÷ 2))
end
bench("full history (1:$n)") do
    set_data_to!(work, base, 1:n)
end

# ── 2. value(Asset) ───────────────────────────────────────────────────────────
println("\n=== value(Asset) + getindex ===")
a = first(values(M.data))
bench("value(a)") do
    value(a)
end
bench("a[\"Close\"]  (full row)") do
    a["Close"]
end
bench("a[\"Close\", $n]  (single element)") do
    a["Close", n]
end

# ── 3. length(Market) ─────────────────────────────────────────────────────────
println("\n=== length(Market) ===")
bench("length(M) × 10 000 calls") do
    for _ in 1:10_000
        length(M)
    end
end

# ── 4. returns_matrix ─────────────────────────────────────────────────────────
println("\n=== returns_matrix ===")
bench("window 252 bars") do
    returns_matrix(M, 1:252)
end
bench("full history ($n bars)") do
    returns_matrix(M)
end

# ── 5. full runTest — no-op strategy ──────────────────────────────────────────
println("\n=== full runTest (no-op strategy) ===")

function noop_init(s) end
function noop_next(s) end
mutable struct NoopStrat <: Strategy
    broker::Broker
    market::Market
    NoopStrat(b::Broker) = new(b, b.market)
end
@strategyMethods NoopStrat noop_next noop_init

bench("runTest $n bars × $(length(M.data)) assets") do
    bt = Backtest(copy(M), NoopStrat, 100_000)
    runTest(bt)
end

# ── 6. processAll! in isolation ───────────────────────────────────────────────
println("\n=== processAll! (no open positions) ===")
bt2 = Backtest(copy(M), NoopStrat, 100_000)
B   = bt2.broker
bench("processAll! × 10 000 calls") do
    for _ in 1:10_000
        processAll!(B)
    end
end

println("\nDone.")
