
"""
    Derivative

Abstract type for all derivatives.
"""
abstract type Derivative end

Base.show(io::IO, D::Derivative) =
  print(io, "Derivative of Type '$(name(D))' on $(D.underlying.ticker)")

"""
    u_value(D::Derivative)

Current value of the derivative's underlying asset.

```jldoctest
Random.seed!(1);
A=asset();
u_value(Buy(A,10))
# output

9.455734786039033
```
"""
@inline function u_value(D::Derivative)
  return value(D.underlying)
end

"""
    payoff(D::Derivative, x)

The derivative's payoff evaluated at underlying value `x`.

```jldoctest
Random.seed!(1);
A=asset();
payoff(Buy(A,10), 5.0)
# output

5.0
```
"""
function payoff end

"""
    value(D::Derivative)

Current mark-to-market value of the derivative.

```jldoctest
Random.seed!(1);
A=asset();
value(Buy(A,10))
# output

9.455734786039033
```
"""
@inline function value(D::Derivative)
  return payoff(D, u_value(D))
end

"""
    abs_return(D::Derivative)

Unrealized P&L: current value minus entry price.

```jldoctest
Random.seed!(1);
A=asset();
abs_return(Buy(A,10))
# output

-9.999999999999998
```
"""
function abs_return(D::Derivative)
  return payoff(D, u_value(D) - D.price)
end

"""
    pct_return(D::Derivative)

Unrealized P&L as a fraction of the entry price.

```jldoctest
Random.seed!(1);
A=asset();
pct_return(Buy(A,10))
# output

-0.5139872695620706
```
"""
function pct_return(D::Derivative) ##Check that this is correct
  return abs_return(D) / D.price
end

"""
    log_return(D::Derivative)

Log return of current value over entry price (`-Inf` if the value is non-positive).

```jldoctest
Random.seed!(1);
A=asset();
log_return(Buy(A,10))
# output

-0.7215204611079813
```
"""
function log_return(D::Derivative)
  value(D) <= 0 ? -Inf : log(value(D) / D.price)
end

"""
    name(D::Derivative)

The derivative's type name.

```jldoctest
Random.seed!(1);
A=asset();
name(Buy(A,10))
# output

"Buy"
```
"""
name(D::Derivative) = String(Symbol(typeof(D)))

"""
    price(D::Derivative)

The derivative's entry price, can be negative.

```jldoctest
Random.seed!(1);
A=asset();
price(Buy(A,10))
# output

19.45573478603903
```
"""
price(D::Derivative) = D.price

"""
    InstrumentKey(ticker::String, kind::Symbol, strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing})

Hashable identifier under which positions net. Two fills net into the same position iff
their keys are equal: same ticker, same derivative type, same strike (options) and same
expiry (short options). `Buy` and `Sell` on one ticker are distinct keys and do not net
against each other.

```jldoctest
InstrumentKey("AAPL", :Buy, nothing, nothing)
# output

InstrumentKey("AAPL", :Buy, nothing, nothing)
```
"""
struct InstrumentKey
  ticker::String
  kind::Symbol
  strike::Union{Float64,Nothing}    # nothing for non-option legs
  expiry::Union{Int,Nothing}        # nothing unless a dated (short) option
end

"""
    instrument_key(D::Derivative)

The `InstrumentKey` a given derivative's fills net under.

```jldoctest
Random.seed!(1);
A=asset();
instrument_key(Buy(A,10))
# output

InstrumentKey("BJSQ", :Buy, nothing, nothing)
```
"""
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
Orcus.print_props(B)
# output

========================================
Assets: KPGR
Derivative type: Derivative of Type 'Buy' on KPGR
Underlying value: 47.33678213108721
Derivative value: 47.33678213108721
Price paid: 57.33678213108721
Strike price: None
Absolute return: -10.0
Percentage return: -0.174408113401574
Log return: -0.1916547115821651
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
  if isdefined(Main, Name)
    existing = getproperty(Main, Name)
    existing isa Type && existing <: Derivative ||
      error("Symbol \"$(Name)\" is already defined and is not an Orcus Derivative")
  end

  # Redefining a struct in place is not supported by Julia (errors on differing
  # fields); instead generate a fresh internal type each call and rebind the
  # public name to it via a plain global, which Julia allows to be reassigned.
  InternalName = Symbol(Name, :_, _unique_type_suffix())

  strct = quote
    mutable struct $InternalName <: Derivative
      underlying::Asset
      price::Float64
      function $InternalName(underlying::Asset, premium::Number=0)
        this = new()
        this.underlying = underlying
        this.price = Float64($price_func(value(underlying), premium))
        return this
      end
    end
    # payoff dispatched on the concrete type — no boxed Function field
    Orcus.payoff(::$InternalName, x) = ($structure)(x)
    Base.nameof(::Type{$InternalName}) = $(QuoteNode(Name))
    Base.show(io::IO, ::Type{$InternalName}) = print(io, $(QuoteNode(Name)))
  end
  return eval(
    quote
      $strct
      global $Name = $InternalName
      export $Name
    end,
  )
end

"""
    Buy(underlying::Asset, premium::Number=0)

A long position in the underlying asset itself.

```jldoctest
Random.seed!(1);
A=asset();
Buy(A,10).price
# output

19.45573478603903
```
"""
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

"""
    Sell(underlying::Asset, premium::Number=0)

A short position in the underlying asset itself.

```jldoctest
Random.seed!(1);
A=asset();
Sell(A,10).price
# output

0.5442652139609674
```
"""
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

"""
    LongCall(underlying::Asset, strike::Number, premium::Number=0)

A long call option on the underlying asset.

```jldoctest
Random.seed!(1);
A=asset();
payoff(LongCall(A,100.0,5), 110.0)
# output

10.0
```
"""
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

"""
    LongPut(underlying::Asset, strike::Number, premium::Number=0)

A long put option on the underlying asset.

```jldoctest
Random.seed!(1);
A=asset();
payoff(LongPut(A,100.0,5), 90.0)
# output

10.0
```
"""
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

"""
    ShortCall(underlying::Asset, strike::Number, premium::Number=0, expiry_days::Int=30)

A short (written) call option on the underlying asset.

```jldoctest
Random.seed!(1);
A=asset();
payoff(ShortCall(A,100.0,5), 110.0)
# output

-10.0
```
"""
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

"""
    ShortPut(underlying::Asset, strike::Number, premium::Number=0, expiry_days::Int=30)

A short (written) put option on the underlying asset.

```jldoctest
Random.seed!(1);
A=asset();
payoff(ShortPut(A,100.0,5), 90.0)
# output

-10.0
```
"""
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
