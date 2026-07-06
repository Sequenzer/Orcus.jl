"""
    MarginModel

Abstract type for margin/leverage models. Governs how much of a same-direction long open/add
is cash-secured vs. broker-financed (`initial_margin_pct`), the cash required to open/add a
short as a fraction of its notional (`short_margin_rate`), the account-level equity threshold
below which the whole book is liquidated (`maintenance_margin_pct`), and the per-bar rate
charged on financed-long and short exposure (`borrow_rate`).

`initial_margin_pct` and `short_margin_rate` are kept separate (not one shared "leverage"
number) because `NoMargin`'s today-behavior is asymmetric: longs are fully cash-secured
(`initial_margin_pct == 1.0`, unchanged from before margin models existed) while shorts are
entirely unconstrained (`short_margin_rate == 0.0`, also unchanged) — a single shared fraction
couldn't represent both defaults at once.

Implement a new model by adding methods for all four functions.
"""
abstract type MarginModel end

"""
    NoMargin()

No leverage, no liquidation, no borrow fee — the default, so existing backtests behave
exactly as before margin models existed. Longs are fully cash-secured
(`initial_margin_pct == 1.0`); shorts are unconstrained (`short_margin_rate == 0.0`, today's
exact behavior); the maintenance check and borrow-fee accrual are no-ops.
"""
struct NoMargin <: MarginModel end
initial_margin_pct(::NoMargin) = 1.0
short_margin_rate(::NoMargin) = 0.0
maintenance_margin_pct(::NoMargin) = 0.0
borrow_rate(::NoMargin) = 0.0

"""
    RegTMargin(initial_pct, maintenance_pct, borrow_rate)

A configurable leverage model — not a regulatory-accurate Reg-T implementation, just named
after the familiar initial/maintenance-margin shape. `initial_pct` governs leverage symmetrically
for both same-direction long opens/adds (`initial_margin_pct`) and short opens/adds
(`short_margin_rate`) — one number, two roles.

- `initial_pct`     — fraction of notional that must be cash-secured on a same-direction long
                       open/add (e.g. `0.5` → 2x leverage); the rest is broker-financed. For a
                       short, the fraction of its notional that must be on hand to open it.
- `maintenance_pct` — fraction of gross open position value that account equity must stay
                       above; falling below it liquidates the whole book.
- `borrow_rate`      — per-bar rate charged on the broker-financed portion of margin longs
                       and on the full notional of open shorts.
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
