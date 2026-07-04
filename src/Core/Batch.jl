
export batch_backtest

"""
    batch_backtest(market, strategy, cash, grid; threaded=true, cost_model=NoCost(), progress=false)

Run a parameter sweep of `strategy` over `market`, one backtest per entry of `grid`, returning
a `Vector{Backtest}` **in input order**.

Each job is fully isolated: the runner deep-`copy`s `market` (so the shared per-asset `visible`
cursor and any indicators attached in `init` are private to the job) and builds its own
`Backtest`. With that isolation, jobs run on separate threads with no shared mutable state — the
threaded result is identical to the sequential one.

`grid` is a vector of `NamedTuple`s forwarded as keyword arguments to the strategy constructor.
Declare the swept parameters as typed fields with [`@generate_strategy`](@ref) (or a custom
`@strategy_methods` struct whose constructor accepts the same keywords):

```julia
@generate_strategy SMAcross cross_next cross_init fast::Int=10 slow::Int=20
res = batch_backtest(market([copy(AAPL)]), SMAcross, 10_000,
                     [(fast=5, slow=20), (fast=10, slow=30)])
```

Keyword arguments:
- `threaded`  – run jobs across threads (default `true`; falls back to sequential when only one
  thread is available). Start Julia with `-t auto`/`-t N` to use more than one thread.
- `cost_model` – `CostModel` applied to every job's broker (default `NoCost()`).
- `progress`  – when `true`, log elapsed time and ETA as jobs complete (default `false`, quiet).
"""
function batch_backtest(market::Market, strategy::Type, cash::Real,
  grid::AbstractVector;
  threaded::Bool=true, cost_model::CostModel=NoCost(),
  progress::Bool=false)
  return batch_backtest(length(grid); threaded=threaded, progress=progress) do i
    M = copy(market)                      # private market → private cursor + indicators
    run_test(Backtest(M, strategy, cash; params=grid[i], cost_model=cost_model))
  end
end

"""
    batch_backtest(builder, n; threaded=true, progress=false) -> Vector{Backtest}

Lower-level form: run `n` jobs where `builder(i)` returns an already-isolated `Backtest` (its own
copied or freshly loaded market). The runner executes and collects them, but performs **no**
implicit market copy — the builder owns isolation. Use this for sweeps that vary the universe
itself rather than just strategy parameters:

```julia
res = batch_backtest(length(universes)) do i
    run_test(Backtest(market([copy(a) for a in universes[i]]), MyStrat, 10_000))
end
```
"""
function batch_backtest(builder, n::Integer; threaded::Bool=true, progress::Bool=false)
  results = Vector{Backtest}(undef, n)
  use_threads = threaded && Threads.nthreads() > 1

  t0 = time()
  done = Threads.Atomic{Int}(0)
  plock = ReentrantLock()
  report =
    i -> begin
      progress || return nothing
      c = Threads.atomic_add!(done, 1) + 1
      lock(plock) do
        el = time() - t0
        eta = c == n ? 0.0 : el * (n - c) / c
        @printf("[batch_backtest] %d/%d  elapsed %.1fs  eta %.1fs\n", c, n, el, eta)
      end
    end

  if use_threads
    Threads.@threads :dynamic for i in 1:n
      results[i] = builder(i)
      report(i)
    end
  else
    for i in 1:n
      results[i] = builder(i)
      report(i)
    end
  end
  return results
end
