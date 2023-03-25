using Dates
using UnicodePlots: lineplot

include("Asset.jl")

abstract type Derivative end


function uValue(D::Derivative)
    return value(D.underlying)
end
function value(D::Derivative)
    return D.structure(uValue(D))
end
function absReturn(D::Derivative)
    return D.structure(uValue(D)-D.price)
end
function pctReturn(D::Derivative)
    return absReturn(D)/D.price
end
function logReturn(D::Derivative)
    value(D)<=0 ? -Inf : log(value(D)/D.price);
end


"""
    plot(D::<Derivative)

Plots the payofstructure.

# Examples

A=Asset();
B=Buy(A,10);
plot(B)
"""
function plot(D::Derivative)
    f=D.structure
    v=uValue(D)
    x=range(v-v/2,v+v/2)
    lineplot(x,f.(x), title=D.underlying.ticker, name=D.name, xlabel="x", ylabel="y")
end
 
"""
    printProps(D::Derivative)

Print all the current properties of the input derivative. 

# Examples

```jldoctest
A = Asset();
B = Buy(A,10)
printProps(B)
# output

100
```

"""
function printProps(D::Derivative)
    if hasproperty(D,:strike) 
        str = D.strike
    else
        str = "None"
    end
    otp ="="^40*"\n"*"""
    Assets: $(D.underlying.ticker)
    Derivative type: $(D.name)
    Underlying value: $(uValue(D))
    Derivative value: $(value(D))
    Price paid: $(D.price)
    Strike price: $(str)
    Absolute return: $(absReturn(D))
    Percentage return: $(pctReturn(D))
    Log return: $(logReturn(D))
    """*"="^40
    print(otp)
end

"""


"""
mutable struct Buy <: Derivative
    underlying::Asset
    structure::Function
    name::String
    price::Number
    function Buy(underlying::Asset,premium::Number=0)
        this = new()
        this.underlying=underlying
        this.structure = x->x
        this.name = "Buy"
        this.price = value(underlying) + premium 
        return this
    end
end




mutable struct Sell <: Derivative
    underlying::Asset
    structure::Function
    name::String
    price::Number
    function Sell(underlying::Asset,premium::Number=0)
        this = new()
        this.underlying=underlying
        this.structure = x->-x
        this.name = "Sell"
        this.price = -value(underlying) + premium 
        return this
    end
end

mutable struct LongCall <: Derivative
    underlying::Asset
    structure::Function
    name::String
    price::Number
    strike::Number
    function LongCall(underlying::Asset,strike::Number,premium::Number=0)
        this = new()
        this.underlying=underlying
        this.structure = x-> max(x-strike,0)
        this.name = "Long Call"
        this.price = premium 
        this.strike = strike
        return this
    end
end

mutable struct LongPut <: Derivative
    underlying::Asset
    structure::Function
    name::String
    price::Number
    strike::Number
    function LongPut(underlying::Asset,strike::Number,premium::Number=0)
        this = new()
        this.underlying=underlying
        this.structure = x-> max(-x+strike,0)
        this.name = "Long Put"
        this.price = premium 
        this.strike = strike
        return this
    end
end

mutable struct ShortCall <: Derivative
    underlying::Asset
    structure::Function
    name::String
    price::Number
    strike::Number
    function ShortCall(underlying::Asset,strike::Number,premium::Number=0)
        this = new()
        this.underlying=underlying
        this.structure = x-> min(-x+strike,0)
        this.name = "Short Call"
        this.price = -premium 
        this.strike = strike
        return this
    end
end

mutable struct ShortPut <: Derivative
    underlying::Asset
    structure::Function
    name::String
    price::Number
    strike::Number
    function ShortPut(underlying::Asset,strike::Number,premium::Number=0)
        this = new()
        this.underlying=underlying
        this.structure = x-> min(x-strike,0)
        this.name = "Short Put"
        this.price = -premium 
        this.strike = strike
        return this
    end
end

#SP=ShortPut(x,100,10)
#printProps(SP)
#B=Buy(x)
#printProps(B)
#plot(SP)
