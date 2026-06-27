#Position

export
    Position,
    volume,
    value,
    uValue,
    apply_trade!,
    is_closed,
    realized_pnl,
    requestToClose

"""
    Position

A netted position in a single instrument (identified by `instrument_key`). All fills on
the same instrument aggregate here:

- `net_qty`     — signed open quantity; the position is closed when this reaches 0.
- `avg_cost`    — weighted-average per-unit entry price, in the `price(derivative)`
                  convention (raw, *excluding* fees).
- `realized_pnl`— realized trading P&L net of all commissions and slippage charged on
                  this instrument.

Fees are *not* folded into `avg_cost` (so mark-to-market basis stays clean); they are
subtracted from `realized_pnl` as they occur. Equity (`cash + Σ value(P)`) is the source
of truth and already reflects fees via the cash ledger.

```jldoctest
A = asset()
P = Position(Buy(A, 0))
apply_trade!(P, 10.0, value(A), 0.0)   # open 10 @ spot
is_closed(P)
# output

false
```
"""
mutable struct Position{D<:Derivative}
    derivative::D            # concrete type parameter → value(P) is type-stable (no boxing)
    net_qty::Float64         # signed; 0 == closed
    avg_cost::Float64        # per-unit weighted-avg entry (raw, fee-exclusive)
    realized_pnl::Float64
    requestToClose::Bool

    function Position(D::Der) where {Der<:Derivative}
        self = new{Der}()
        self.derivative     = D
        self.net_qty        = 0.0
        self.avg_cost       = 0.0
        self.realized_pnl   = 0.0
        self.requestToClose = false
        return self
    end
end

Base.show(io::IO, P::Position) = is_closed(P) ?
    print(io, "A closed position in $(P.derivative.underlying.ticker)") :
    print(io, "An open position of $(P.net_qty) $(name(P.derivative)) on $(P.derivative.underlying.ticker)")

volume(P::Position)    = P.net_qty
value(P::Position)     = P.net_qty * value(P.derivative)
uValue(P::Position)    = P.net_qty * uValue(P.derivative)
price(P::Position)     = P.net_qty * P.avg_cost                 # cost basis
absReturn(P::Position) = value(P) - price(P)                    # unrealized
pctReturn(P::Position) = price(P) == 0 ? 0.0 : absReturn(P) / abs(price(P))
logReturn(P::Position) = value(P) <= 0 ? -Inf : log(value(P) / price(P))
realized_pnl(P::Position) = P.realized_pnl

is_closed(P::Position) = P.net_qty == 0.0

"""
    apply_trade!(P::Position, qty::Real, fill_price::Real, fee::Real=0.0)

Fold a fill of signed `qty` units at per-unit `fill_price` (raw, fee-exclusive) into the
netted position. `fee` is the total commission+slippage on the fill; it is subtracted
from `realized_pnl`.

- Adding (same sign / opening): updates the weighted-average `avg_cost`.
- Reducing/closing (opposite sign): realizes P&L on the closed quantity. If the fill
  flips the position through zero, the remainder opens a fresh lot at `fill_price`.
"""
function apply_trade!(P::Position, qty::Real, fill_price::Real, fee::Real=0.0)
    qty        = Float64(qty)
    fill_price = Float64(fill_price)
    P.realized_pnl -= Float64(fee)

    if P.net_qty == 0.0 || sign(qty) == sign(P.net_qty)
        # opening or adding in the same direction → weighted average
        new_qty     = P.net_qty + qty
        P.avg_cost  = (P.avg_cost * P.net_qty + fill_price * qty) / new_qty
        P.net_qty   = new_qty
    else
        # reducing, closing, or flipping
        closed = min(abs(qty), abs(P.net_qty))
        P.realized_pnl += closed * (fill_price - P.avg_cost) * sign(P.net_qty)
        new_qty = P.net_qty + qty
        if new_qty != 0.0 && sign(new_qty) != sign(P.net_qty)
            P.avg_cost = fill_price   # flipped through zero → new lot
        end
        P.net_qty = new_qty
        new_qty == 0.0 && (P.avg_cost = 0.0)
    end
    return P
end

"""
    requestToClose(P::Position)

Set the position's close flag. To have the broker actually close it, request the close
through the broker API (`requestToCloseAll!`/`requestToClose!`), which also arms the broker's
per-bar resolve; `resolvePortfolio!` skips its scan unless a broker-level close was requested.
"""
function requestToClose(P::Position)
    P.requestToClose = true
    return P
end

"""
    plot(P::Position)

Plot the payoff structure of the underlying derivative.
"""
function plot(P::Position)
    plot(P.derivative)
end
