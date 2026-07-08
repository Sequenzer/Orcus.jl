# Strategy authoring

A strategy is just two functions — `init`, run once before the backtest loop, and `next`,
run once per bar — wired to a concrete struct via `@generate_strategy`; see the
[Tutorial](tutorial.md) for a worked example.

```@docs
Strategy
init
next
@generate_strategy
@strategy_methods
```

```@index
Pages = ["core_strategy.md"]
```
