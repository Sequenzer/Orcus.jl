"""
    Position

A netted position in a single instrument (identified by `instrument_key`). All fills on
the same instrument aggregate here:

- `net_qty`     — signed open quantity; the position is closed when this reaches 0.
- `avg_cost`    — weighted-average per-unit entry price, in the `price(derivative)`
                  convention (raw, *excluding* fees).
- `realized_pnl`— realized trading P&L net of all commissions and slippage charged on
                  this instrument.
- `loan`        — broker-financed dollar amount still owed against this position (`0.0`
                  unless opened under a margin model with `initial_margin_pct < 1.0`).

Fees are *not* folded into `avg_cost` (so mark-to-market basis stays clean); they are
subtracted from `realized_pnl` as they occur. Equity (`cash + Σ value(P) - Σ loan`) is the
source of truth and already reflects fees via the cash ledger.

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
  loan::Float64            # broker-financed $ still owed against this position; 0.0 unless margin-financed
  requestToClose::Bool

  function Position(D::Der) where {Der<:Derivative}
    self = new{Der}()
    self.derivative = D
    self.net_qty = 0.0
    self.avg_cost = 0.0
    self.realized_pnl = 0.0
    self.loan = 0.0
    self.requestToClose = false
    return self
  end
end

Base.show(io::IO, P::Position) =
  if is_closed(P)
    print(io, "A closed position in $(P.derivative.underlying.ticker)")
  else
    print(
      io,
      "An open position of $(P.net_qty) $(name(P.derivative)) on $(P.derivative.underlying.ticker)",
    )
  end

volume(P::Position) = P.net_qty
@inline value(P::Position) =
  _fx_convert(P.derivative.underlying, P.net_qty * value(P.derivative))
u_value(P::Position) = P.net_qty * u_value(P.derivative)
price(P::Position) = P.net_qty * P.avg_cost                 # cost basis
abs_return(P::Position) = value(P) - price(P)                    # unrealized
pct_return(P::Position) = price(P) == 0 ? 0.0 : abs_return(P) / abs(price(P))
log_return(P::Position) = value(P) <= 0 ? -Inf : log(value(P) / price(P))
realized_pnl(P::Position) = P.realized_pnl

is_closed(P::Position) = P.net_qty == 0.0

"""
    apply_trade!(P::Position, qty::Real, fill_price::Real, fee::Real=0.0; borrowed::Real=0.0)

Fold a fill of signed `qty` units at per-unit `fill_price` (raw, fee-exclusive) into the
netted position. `fee` is the total commission+slippage on the fill; it is subtracted
from `realized_pnl`. `borrowed` is the broker-financed dollar amount of *this* fill
(`0.0` unless opening/adding under a margin model) — see `loan` on `Position`.

- Adding (same sign / opening): updates the weighted-average `avg_cost` and accumulates
  `loan += borrowed`.
- Reducing/closing (opposite sign): realizes P&L on the closed quantity and repays `loan`
  proportionally to the fraction of the position closed. If the fill flips the position
  through zero, the remainder opens a fresh lot at `fill_price` (with `loan == 0.0`, since
  the proportional repay above already drove it there on a full close).
"""
function apply_trade!(
  P::Position, qty::Real, fill_price::Real, fee::Real=0.0; borrowed::Real=0.0
)
  qty = Float64(qty)
  fill_price = Float64(fill_price)
  P.realized_pnl -= Float64(fee)

  if P.net_qty == 0.0 || sign(qty) == sign(P.net_qty)
    # opening or adding in the same direction → weighted average
    new_qty = P.net_qty + qty
    P.avg_cost = (P.avg_cost * P.net_qty + fill_price * qty) / new_qty
    P.loan += Float64(borrowed)
    P.net_qty = new_qty
  else
    # reducing, closing, or flipping
    closed = min(abs(qty), abs(P.net_qty))
    P.realized_pnl += closed * (fill_price - P.avg_cost) * sign(P.net_qty)
    P.loan -= P.loan * (closed / abs(P.net_qty))
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
    request_to_close(P::Position)

Set the position's close flag. To have the broker actually close it, request the close
through the broker API (`request_to_close_all!`/`request_to_close!`), which also arms the broker's
per-bar resolve; `resolve_portfolio!` skips its scan unless a broker-level close was requested.
"""
function request_to_close(P::Position)
  P.requestToClose = true
  return P
end
