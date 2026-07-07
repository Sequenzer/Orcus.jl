"""
    Trade(O::Order{D,K}, date::Int=length(O.derivative.underlying)) where {D<:Derivative,K<:OrderKind}
    Trade(derivative::D, volume::Real, date::Int, delta_cash::Real=0.0) where {D<:Derivative}

A recorded fill: the derivative traded, signed volume, bar date, and net cash impact.

```jldoctest
Random.seed!(1234);
A = asset();
B = Buy(A, 10);
O = order(B, 100);
T = Trade(O);
value(T)
# output

6887.71178523604
```
"""
mutable struct Trade{D<:Derivative}
  derivative::D
  volume::Float64
  date::Int
  delta_cash::Float64
  function Trade(
    O::Order{D,K}, date::Int=length(O.derivative.underlying)
  ) where {D<:Derivative,K<:OrderKind}
    self = new{D}()
    self.derivative = O.derivative
    self.volume = Float64(O.volume)
    self.date = date
    self.delta_cash = 0.0   # set by the broker at fill time
    return self
  end
  # Direct constructor — used by close-outs, which know the concrete derivative type.
  function Trade(
    derivative::D, volume::Real, date::Int, delta_cash::Real=0.0
  ) where {D<:Derivative}
    self = new{D}()
    self.derivative = derivative
    self.volume = Float64(volume)
    self.date = date
    self.delta_cash = Float64(delta_cash)
    return self
  end
end

Base.show(io::IO, T::Trade) = print(
  io,
  "A $(T.derivative.underlying.ticker) trade of $(T.volume) $(name(T.derivative)) on $(T.date)",
)

"""
    value(T::Trade)

Current mark-to-market value of the trade's volume at its derivative's current value.

```jldoctest
Random.seed!(1234);
A = asset();
B = Buy(A, 10);
O = order(B, 100);
T = Trade(O);
value(T)
# output

6887.71178523604
```
"""
value(T::Trade) = T.volume * value(T.derivative)

"""
    price(T::Trade)

Cost basis of the trade's volume at its derivative's entry price.

```jldoctest
Random.seed!(1234);
A = asset();
B = Buy(A, 10);
O = order(B, 100);
T = Trade(O);
price(T)
# output

7887.71178523604
```
"""
price(T::Trade) = T.volume * price(T.derivative)
