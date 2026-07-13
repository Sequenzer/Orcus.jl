"""
    Position(D::Derivative)

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
Random.seed!(1);
A = asset()
P = Position(Buy(A, 0))
Orcus.apply_trade!(P, 10.0, value(A), 0.0)   # open 10 @ spot
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

"""
    volume(P::Position)

The position's signed net quantity.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
volume(P)
# output

10.0
```
"""
volume(P::Position) = P.net_qty

"""
    value(P::Position)

Current mark-to-market value of the position, in the broker's base currency.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
value(P)
# output

94.55734786039032
```
"""
@inline value(P::Position) =
  _fx_convert(P.derivative.underlying, P.net_qty * value(P.derivative))

"""
    u_value(P::Position)

Current value of the position in the underlying's own price units, before fx conversion.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
u_value(P)
# output

94.55734786039032
```
"""
u_value(P::Position) = P.net_qty * u_value(P.derivative)

"""
    price(P::Position)

Cost basis of the position (`net_qty * avg_cost`).

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
price(P)
# output

94.55734786039032
```
"""
price(P::Position) = P.net_qty * P.avg_cost

"""
    abs_return(P::Position)

Unrealized P&L: current value minus cost basis.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
abs_return(P)
# output

0.0
```
"""
abs_return(P::Position) = value(P) - price(P)

"""
    pct_return(P::Position)

Unrealized P&L as a fraction of the cost basis (`0.0` if the cost basis is `0.0`).

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
pct_return(P)
# output

0.0
```
"""
pct_return(P::Position) = price(P) == 0 ? 0.0 : abs_return(P) / abs(price(P))

"""
    log_return(P::Position)

Log return of current value over cost basis (`-Inf` if the value is non-positive).

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
log_return(P)
# output

0.0
```
"""
log_return(P::Position) = value(P) <= 0 ? -Inf : log(value(P) / price(P))

"""
    realized_pnl(P::Position)

Realized trading P&L on the position, net of commissions and slippage.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
realized_pnl(P)
# output

0.0
```
"""
realized_pnl(P::Position) = P.realized_pnl

"""
    is_closed(P::Position)

Whether the position's net quantity is zero.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
is_closed(P)
# output

true
```
"""
is_closed(P::Position) = P.net_qty == 0.0

"""
    apply_trade!(P::Position, qty::Real, fill_price::Real, fee::Real=0.0; borrowed::Real=0.0)

Fold a fill of signed `qty` units at per-unit `fill_price` into the netted position, updating
cost basis on same-direction fills or realizing P&L on reducing/closing/flipping fills.
`fee` is subtracted from `realized_pnl`; `borrowed` accumulates into `loan`.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.apply_trade!(P, 10.0, value(A), 0.0);
P.net_qty
# output

10.0
```
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

Set the position's close flag. Use the broker API
([`request_to_close_all!`](@ref)/[`request_to_close!`](@ref)) to actually have it closed.

```jldoctest
Random.seed!(1);
A=asset();
P=Position(Buy(A,0));
Orcus.request_to_close(P);
P.requestToClose
# output

true
```
"""
function request_to_close(P::Position)
  P.requestToClose = true
  return P
end
