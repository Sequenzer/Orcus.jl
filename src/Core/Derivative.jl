
export
  Derivative,
  @generate_derivative,
  Buy,
  Sell,
  LongCall,
  LongPut,
  ShortCall,
  ShortPut,
  print_props,
  u_value,
  value,
  name,
  abs_return,
  pct_return,
  log_return,
  payoff,
  instrument_key,
  InstrumentKey

"""
    Derivative

Abstract type for all derivatives.
"""
abstract type Derivative end

Base.show(io::IO, D::Derivative) =
  print(io, "Derivative of Type '$(name(D))' on $(D.underlying.ticker)")

@inline function u_value(D::Derivative)
  return value(D.underlying)
end

"""
    payoff(D::Derivative, x)

The derivative's payoff structure evaluated at underlying value `x`. Dispatched on the
concrete type (no boxed `Function` field), so `value(D)` is type-stable and inlinable.
"""
function payoff end

@inline function value(D::Derivative)
  return payoff(D, u_value(D))
end
function abs_return(D::Derivative)
  return payoff(D, u_value(D) - D.price)
end
function pct_return(D::Derivative) ##Check that this is correct
  return abs_return(D) / D.price
end
function log_return(D::Derivative)
  value(D) <= 0 ? -Inf : log(value(D) / D.price)
end
name(D::Derivative) = String(Symbol(typeof(D)))
price(D::Derivative) = D.price

"""
    instrument_key(D::Derivative)

Hashable identifier under which positions net. Two fills net into the same position iff
their keys are equal: same ticker, same derivative type, same strike (options) and same
expiry (short options). `Buy` and `Sell` on one ticker are distinct keys and do not net
against each other.
"""
struct InstrumentKey
  ticker::String
  kind::Symbol
  strike::Union{Float64,Nothing}    # nothing for non-option legs
  expiry::Union{Int,Nothing}        # nothing unless a dated (short) option
end

instrument_key(D::Derivative) = InstrumentKey(
  D.underlying.ticker,
  nameof(typeof(D)),
  hasproperty(D, :strike) ? Float64(D.strike) : nothing,
  hasproperty(D, :expiry_days) ? Int(D.expiry_days) : nothing,
)

"""
    print_props(D::Derivative)

Print all the current properties of the input derivative. 

# Examples

```jldoctest
Random.seed!(456);
A = asset();
B = Buy(A,10);
print_props(B)
# output

========================================
Assets: KPGR
Derivative type: Buy
Underlying value: 100.16749318215984
Derivative value: 100.16749318215984
Price paid: 110.16749318215984
Strike price: None
Absolute return: -10.0
Percentage return: -0.09077087724475305
Log return: -0.09515815632970726
========================================
```

"""
function print_props(D::Derivative)
  if hasproperty(D, :strike)
    str = D.strike
  else
    str = "None"
  end
  otp = "="^40 * "\n" * """
       Assets: $(D.underlying.ticker)
       Derivative type: $(D)
       Underlying value: $(u_value(D))
       Derivative value: $(value(D))
       Price paid: $(D.price)
       Strike price: $(str)
       Absolute return: $(abs_return(D))
       Percentage return: $(pct_return(D))
       Log return: $(log_return(D))
       """ * "="^40
  print(otp)
end

"""
    @generate_derivative(Name::Symbol, structure::Expr, price_func::Expr)

Macro to generate a new derivative type.


# Examples

```jldoctest
@generate_derivative NewBuy x->x (val,premium)->val+premium

x = asset()
name(NewBuy(x,10))

# output

"NewBuy"
```
"""
macro generate_derivative(Name::Symbol, structure::Expr, price_func::Expr)
  isdefined(Main, Name) && error("Symbol \"$(Name)\" is already defined")

  strct = quote
    mutable struct $Name <: Derivative
      underlying::Asset
      price::Float64
      function $Name(underlying::Asset, premium::Number=0)
        this = new()
        this.underlying = underlying
        this.price = Float64($price_func(value(underlying), premium))
        return this
      end
    end
    # payoff dispatched on the concrete type — no boxed Function field
    Orcus.payoff(::$Name, x) = ($structure)(x)
  end
  return eval(
    quote
      export $Name

      $strct
    end,
  )
end

mutable struct Buy <: Derivative
  underlying::Asset
  price::Float64
  function Buy(underlying::Asset, premium::Number=0)
    this = new()
    this.underlying = underlying
    this.price = value(underlying) + premium
    return this
  end
end
@inline payoff(::Buy, x) = x

mutable struct Sell <: Derivative
  underlying::Asset
  price::Float64
  function Sell(underlying::Asset, premium::Number=0)
    this = new()
    this.underlying = underlying
    this.price = -value(underlying) + premium
    return this
  end
end
@inline payoff(::Sell, x) = -x

mutable struct LongCall <: Derivative
  underlying::Asset
  price::Float64
  strike::Float64
  function LongCall(underlying::Asset, strike::Number, premium::Number=0)
    this = new()
    this.underlying = underlying
    this.price = premium
    this.strike = strike
    return this
  end
end
payoff(d::LongCall, x) = max(x - d.strike, 0.0)

mutable struct LongPut <: Derivative
  underlying::Asset
  price::Float64
  strike::Float64
  function LongPut(underlying::Asset, strike::Number, premium::Number=0)
    this = new()
    this.underlying = underlying
    this.price = premium
    this.strike = strike
    return this
  end
end
payoff(d::LongPut, x) = max(-x + d.strike, 0.0)

mutable struct ShortCall <: Derivative
  underlying::Asset
  price::Float64
  strike::Float64
  expiry_days::Int    # calendar days to expiry (used by live layer for OCC symbol)
  function ShortCall(underlying::Asset, strike::Number,
    premium::Number=0, expiry_days::Int=30)
    this = new()
    this.underlying = underlying
    this.price = -premium
    this.strike = strike
    this.expiry_days = expiry_days
    return this
  end
end
payoff(d::ShortCall, x) = min(-x + d.strike, 0.0)

mutable struct ShortPut <: Derivative
  underlying::Asset
  price::Float64
  strike::Float64
  expiry_days::Int    # calendar days to expiry (used by live layer for OCC symbol)
  function ShortPut(underlying::Asset, strike::Number,
    premium::Number=0, expiry_days::Int=30)
    this = new()
    this.underlying = underlying
    this.price = -premium
    this.strike = strike
    this.expiry_days = expiry_days
    return this
  end
end
payoff(d::ShortPut, x) = min(x - d.strike, 0.0)
