# Strategy authoring

A strategy is two functions registered with `@generate_strategy Name next_fn init_fn`:

- `init(s::Strategy)` runs once; typically attaches indicators via `apply_indicator`.
- `next(s::Strategy)` runs once per bar.

Inside both, reach the portfolio via `s.broker` and price data via `s.market`. See the
[Quick start](@ref) for a full SMA-crossover example, and [Lib](@ref) for the built-in
`crossover_init`/`crossover_next` strategy.

```@autodocs
Modules = [Orcus]
Pages = ["Core/Strategy.jl"]
Private = false
```

```@index
Pages = ["core_strategy.md"]
```
