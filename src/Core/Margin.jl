"""
    MarginModel

Abstract type for margin/leverage models, governing leverage on longs, cash required for
shorts, the liquidation threshold, and the per-bar financing rate — see
[`initial_margin_pct`](@ref), [`short_margin_rate`](@ref), [`maintenance_margin_pct`](@ref),
[`borrow_rate`](@ref). Implement a new model by adding methods for all four.
"""
abstract type MarginModel end

"""
    NoMargin()

No leverage, no liquidation, no borrow fee — the default, so existing backtests behave
exactly as before margin models existed. Longs are fully cash-secured
(`initial_margin_pct == 1.0`); shorts are unconstrained (`short_margin_rate == 0.0`, today's
exact behavior); the maintenance check and borrow-fee accrual are no-ops.

```jldoctest
NoMargin()
# output

NoMargin()
```
"""
struct NoMargin <: MarginModel end

"""
    initial_margin_pct(m::MarginModel)

Fraction of notional that must be cash-secured on a same-direction long open/add under `m`.

```jldoctest
initial_margin_pct(NoMargin())
# output

1.0
```
"""
initial_margin_pct(::NoMargin) = 1.0
"""
    short_margin_rate(m::MarginModel)

Fraction of notional that must be on hand to open/add a short position under `m`.

```jldoctest
short_margin_rate(NoMargin())
# output

0.0
```
"""
short_margin_rate(::NoMargin) = 0.0

"""
    maintenance_margin_pct(m::MarginModel)

Fraction of gross open position value that account equity must stay above under `m` before
the whole book is liquidated.

```jldoctest
maintenance_margin_pct(NoMargin())
# output

0.0
```
"""
maintenance_margin_pct(::NoMargin) = 0.0

"""
    borrow_rate(m::MarginModel)

Per-bar rate charged on financed-long and short exposure under `m`.

```jldoctest
borrow_rate(NoMargin())
# output

0.0
```
"""
borrow_rate(::NoMargin) = 0.0

"""
    RegTMargin(initial_pct::Real, maintenance_pct::Real, borrow_rate::Real)

A configurable leverage model — not a regulatory-accurate Reg-T implementation, just named
after the familiar initial/maintenance-margin shape. `initial_pct` sets leverage for both
long opens (e.g. `0.5` → 2x leverage) and the cash required to open a short; `maintenance_pct`
sets the liquidation threshold; `borrow_rate` is the per-bar financing rate.

```jldoctest
m=RegTMargin(0.5, 0.25, 0.05);
initial_margin_pct(m)
# output

0.5
```
"""
struct RegTMargin <: MarginModel
  initial_pct::Float64
  maintenance_pct::Float64
  borrow_rate::Float64
end
RegTMargin(initial_pct::Real, maintenance_pct::Real, borrow_rate::Real) =
  RegTMargin(Float64(initial_pct), Float64(maintenance_pct), Float64(borrow_rate))

initial_margin_pct(m::RegTMargin) = m.initial_pct
short_margin_rate(m::RegTMargin) = m.initial_pct
maintenance_margin_pct(m::RegTMargin) = m.maintenance_pct
borrow_rate(m::RegTMargin) = m.borrow_rate
