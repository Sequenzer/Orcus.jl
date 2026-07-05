# Threaded parameter sweep with `batch_backtest`.
#
# Run it with more than one thread to actually parallelize:
#
#     julia --project=examples -t auto examples/batch_sweep.jl
#
# `batch_backtest` deep-copies the market for every job, so the runs are fully isolated
# and the threaded result is identical to a sequential one — see CLAUDE.md "Concurrency".

using Orcus
using Printf

# ── strategy ──────────────────────────────────────────────────────────────────
# The swept parameters are declared as typed fields on the strategy (`fast`, `slow`).
# `init` reads them to attach the right indicators; `next` trades the crossover.
function sweep_init(s::Strategy)
  for (_, a) in s.market.data
    apply_indicator(IndicatorGenerator(simple_average, s.fast), a, "Close", "SMAf")
    apply_indicator(IndicatorGenerator(simple_average, s.slow), a, "Close", "SMAs")
  end
end

function sweep_next(s::Strategy)
  for (_, a) in s.market.data
    n = length(a)
    n < 2 && continue
    (isnan(a["SMAf", n]) || isnan(a["SMAs", n])) && continue
    (isnan(a["SMAf", n - 1]) || isnan(a["SMAs", n - 1])) && continue

    up = a["SMAf", n] > a["SMAs", n] && a["SMAf", n - 1] <= a["SMAs", n - 1]
    down = a["SMAf", n] < a["SMAs", n] && a["SMAf", n - 1] >= a["SMAs", n - 1]

    if up
      request_to_close_all!(s.broker)
      place_order!(s.broker, Order(Buy(a, 5)))
    elseif down
      request_to_close_all!(s.broker)   # go flat, no short
    end
  end
end

# typed param fields → sweepable, and 0 B/bar on the hot path
@generate_strategy SMASweep sweep_next sweep_init fast::Int=10 slow::Int=20

# ── the sweep ─────────────────────────────────────────────────────────────────
M = market([GOOG])     # batch_backtest copies this per job; GOOG itself is never mutated

grid = [(fast=f, slow=s) for f in (5, 10, 15, 20) for s in (30, 50, 100) if f < s]

@printf("Sweeping %d (fast, slow) combos on %d thread(s)…\n\n",
  length(grid), Threads.nthreads())

results = batch_backtest(M, SMASweep, 10_000, grid; progress=true)

# ── ranked summary ────────────────────────────────────────────────────────────
rows = map(zip(grid, results)) do (p, bt)
  eq = bt.broker.equity_history
  (fast=p.fast, slow=p.slow, equity=eq[end],
    sharpe=sharpe_ratio(eq), trades=length(bt.broker.history))
end
sort!(rows; by=r -> r.sharpe, rev=true)

println("\n fast  slow   final equity    sharpe   trades")
println("─────────────────────────────────────────────")
for r in rows
  @printf("%4d  %4d   %12.2f   %6.2f   %6d\n",
    r.fast, r.slow, r.equity, r.sharpe, r.trades)
end

best = rows[1]
@printf("\nbest by Sharpe: fast=%d slow=%d  (Sharpe %.2f, equity %.2f)\n",
  best.fast, best.slow, best.sharpe, best.equity)
