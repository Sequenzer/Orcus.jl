
"""
    OrderKind

Abstract type for order trigger semantics. A concrete `OrderKind` determines whether/at what
price an `Order` fills on a given bar via [`check_trigger`](@ref).
"""
abstract type OrderKind end

"""
    MarketOrder()

Fills unconditionally at `price(order.derivative)` — the default, unchanged since before order
kinds existed.

```jldoctest
MarketOrder()
# output

MarketOrder()
```
"""
struct MarketOrder <: OrderKind end

"""
    Limit(price::Real)

Resting order that only fills once the bar's range reaches a price at least as good as `price`
(in the underlying asset's own price units). Fills at the better of the bar's open and `price`.

```jldoctest
Limit(100.0)
# output

Limit(100.0)
```
"""
struct Limit <: OrderKind
  price::Float64
end
Limit(price::Real) = Limit(Float64(price))

"""
    Stop(price::Real)

Resting order that fills once the bar's range breaches `price` (in the underlying asset's own
price units) — the mirror image of [`Limit`](@ref). Fills at the worse of the bar's open and
`price`.

```jldoctest
Stop(95.0)
# output

Stop(95.0)
```
"""
struct Stop <: OrderKind
  price::Float64
end
Stop(price::Real) = Stop(Float64(price))

"""
    Order(derivative::Derivative, volume::Real=1, kind::OrderKind=MarketOrder(); allow_partial::Bool=false)

An order to buy or sell a derivative, not yet fulfilled. `volume` is the original requested
quantity and is never mutated; `remaining` tracks the unfilled quantity as partial fills occur.

```jldoctest
A=asset();
B=Buy(A,10);
O=order(B);
O.fulfilled
# output

false
```
"""
mutable struct Order{D<:Derivative,K<:OrderKind}
  derivative::D
  volume::Float64
  kind::K
  allow_partial::Bool
  remaining::Float64
  fulfilled::Bool
  fulfillment_date::Int

  function Order(
    derivative::D, volume::Real=1, kind::K=MarketOrder(); allow_partial::Bool=false
  ) where {D<:Derivative,K<:OrderKind}
    this = new{D,K}()
    this.derivative = derivative
    this.volume = Float64(volume)
    this.kind = kind
    this.allow_partial = allow_partial
    this.remaining = this.volume
    this.fulfilled = false
    return this
  end
end

"""
    order(derivative::Derivative, volume::Real=1, kind::OrderKind=MarketOrder(); allow_partial::Bool=false)

Convenience constructor for an `Order`.

```jldoctest
Random.seed!(1);
A=asset();
order(Buy(A,10)).fulfilled
# output

false
```
"""
order(
  derivative::Derivative,
  volume::Real=1,
  kind::OrderKind=MarketOrder();
  allow_partial::Bool=false,
) =
  Order(derivative, volume, kind; allow_partial=allow_partial)

"""
    limit_order(derivative::Derivative, volume::Real, price::Real; allow_partial::Bool=false)

Convenience constructor for an `Order` with a [`Limit`](@ref) kind.

```jldoctest
Random.seed!(1);
A=asset();
limit_order(Buy(A,10), 10, 95.0).kind
# output

Limit(95.0)
```
"""
limit_order(derivative::Derivative, volume::Real, price::Real; allow_partial::Bool=false) =
  Order(derivative, volume, Limit(price); allow_partial=allow_partial)

"""
    stop_order(derivative::Derivative, volume::Real, price::Real; allow_partial::Bool=false)

Convenience constructor for an `Order` with a [`Stop`](@ref) kind.

```jldoctest
Random.seed!(1);
A=asset();
stop_order(Buy(A,10), 10, 95.0).kind
# output

Stop(95.0)
```
"""
stop_order(derivative::Derivative, volume::Real, price::Real; allow_partial::Bool=false) =
  Order(derivative, volume, Stop(price); allow_partial=allow_partial)

Base.show(io::IO, O::Order) = print(
  io, "Order for $(O.volume) $(name(O.derivative)) on $(O.derivative.underlying.ticker)"
)

"""
    volume(order::Order)

The order's original requested quantity (never mutated as fills occur).

```jldoctest
Random.seed!(1);
A=asset();
volume(order(Buy(A,10), 5))
# output

5.0
```
"""
volume(order::Order) = order.volume

"""
    remaining(order::Order)

Signed quantity still unfilled on `order`.

```jldoctest
Random.seed!(1);
A=asset();
remaining(order(Buy(A,10)))
# output

1.0
```
"""
remaining(order::Order) = order.remaining

"""
    price(order::Order)

The price of a placed order, can be negative.

```jldoctest
Random.seed!(1234);
A=asset();
B=Buy(A,10);
O=order(B,10);
price(O)
# output

788.771178523604
```
"""
price(order::Order) = price(order.derivative) * volume(order)

"""
    fulfill(order::Order, date::Int=length(order.derivative.underlying))

Fulfill an order, returns its price.

```jldoctest
Random.seed!(1234);
A=asset();
B=Buy(A,10);
O=Order(B,10);
fulfill(O,100)
# output

788.771178523604
```
"""
function fulfill(order::Order, date::Int=length(order.derivative.underlying))
  order.fulfilled = true
  order.fulfillment_date = date
  return price(order)
end

"""
    isfulfilled(order::Order)

Returns true if the Order has been fulfilled.

```jldoctest
Random.seed!(1234);
A=asset();
B=Buy(A,10);
O=Order(B,10);
isfulfilled(O)
# output

false
```
"""
isfulfilled(order::Order) = order.fulfilled

"""
    check_trigger(O::Order, B, date::Int)

Whether `O` fills on bar `date`, and at what price, as `(triggered, fill_price)`.
`MarketOrder`s always trigger at `price(O.derivative)`. `Limit`/`Stop` orders on `Buy`/`Sell`
derivatives trigger against the underlying asset's Open/High/Low for `date`.

Not defined for other derivative types (options etc.) — limit/stop orders on them raise
`MethodError` rather than behaving silently wrong.

```jldoctest
Random.seed!(1);
A=asset();
O=Order(Buy(A,10));
check_trigger(O, nothing, 1)
# output

(true, 19.45573478603903)
```
"""
check_trigger(O::Order{D,MarketOrder}, B, date::Int) where {D<:Derivative} =
  (true, price(O.derivative))

function check_trigger(O::Order{D,Limit}, B, date::Int) where {D<:Union{Buy,Sell}}
  A = O.derivative.underlying
  open, low, high = A["Open", date], A["Low", date], A["High", date]
  buy_side = sign(price(O.derivative)) * sign(remaining(O)) > 0
  deriv_sign = sign(price(O.derivative)) >= 0 ? 1.0 : -1.0
  trig = O.kind.price
  if buy_side
    low <= trig || return (false, 0.0)
    return (true, deriv_sign * min(open, trig))
  else
    high >= trig || return (false, 0.0)
    return (true, deriv_sign * max(open, trig))
  end
end

function check_trigger(O::Order{D,Stop}, B, date::Int) where {D<:Union{Buy,Sell}}
  A = O.derivative.underlying
  open, low, high = A["Open", date], A["Low", date], A["High", date]
  buy_side = sign(price(O.derivative)) * sign(remaining(O)) > 0
  deriv_sign = sign(price(O.derivative)) >= 0 ? 1.0 : -1.0
  trig = O.kind.price
  if buy_side
    high >= trig || return (false, 0.0)
    return (true, deriv_sign * max(open, trig))
  else
    low <= trig || return (false, 0.0)
    return (true, deriv_sign * min(open, trig))
  end
end
