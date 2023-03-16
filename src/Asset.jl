using Dates
using Random
using Statistics


include("src/Utils.jl");

export Asset, simple_average, randOHLC, populateOHLC,  value

"""
This is an Asset

# Fields
- ticker: The name of the Asset, by which it should be identified.
- interval: The maximal interval the data can span across.
- prop_funct: The propability function defining the random walk of the data.

# Example
```jldoctest
x=Asset("AAPL")
x.ticker

# output

"AAPL"
```
"""
mutable struct Asset
    ticker::String  
    interval::StepRange{Date, <:Period}
    data::Dict{String,Vector{<:Union{Missing,Number}}}
    function Asset(
        ticker::String;
        interval::StepRange{Date, <:Period}=Date(2010):Dates.Day(5):Date(2020),
        prop_func::Union{Nothing,Function}=nothing)

        this = new()
        this.ticker = ticker
        this.interval= interval
        if prop_func !== nothing
            populateOHLC(this,prop_func)
        end
        return this
    end
    function Asset()
        this=new()
        this.ticker = randstring('A':'Z', 4)
        this.interval=Date(2010):Dates.Day(5):Date(2020)
        this.data = Dict{String,Vector{<:Union{Missing,Number}}}()
        populateOHLC(this)
        return this 
    end
end

"""
    IndicatorGenerator(f::Function,window::Int)

# Fields
- f: The function that will calculate the Indicator,
- window: The window size of the data that will be used to calculate the Indicator.

# Example
```jldoctest
SMA10=IndicatorGenerator(simple_average,10)
SMA10.window

# output
10

"""
mutable struct IndicatorGenerator
    calc_func::Function
    window::Int

    function IndicatorGenerator(
        calc_func::Function,
        window::Int=1
    ) 
        this = new()
        this.calc_func = calc_func
        this.window = window
        return this
    end

end

"""
    calculateIndicator(Ind::IndicatorGenerator,a::Asset,data_key::String)

# Arguments
- Ind: The IndicatorGenerator we fand to calculate data for.
- asset: The Asset for which the indicator is computed.
- data_kes: The key of the data that the indicator is based on.    

# Output
An Array of the Data calculated.

"""
function calculateIndicator(Ind::IndicatorGenerator, asset::Asset, data_key::String)
    data = asset.data[data_key]
    num_points = length(data)

    # Initialize the indicator vector with missing data values
    indicator = Vector{Union{Missing,Number}}(missing, num_points)

    # Calculate the indicator for non-empty data points
        for i in Ind.window:num_points
            if all(!ismissing, data[i-Ind.window+1:i])
                indicator[i] = Ind.calc_func(data[i-Ind.window+1:i])
            end
        end

    return indicator
end

function applyIndicator(
    Ind::IndicatorGenerator,
    asset::Asset,
    data_key::String,
    name::String
    )
    asset.data[name]=calculateIndicator(Ind,asset,data_key)
    
end

"""
    randOHLC(base::Number,n::Int,precision::Int)

The randOHLC function generates n many OHLC datapoints. The precision argument is the number of random trades the values are based on. 

```jldoctest

Random.seed!(1234)
prop_func=x->rand()-0.5
randOHLC(10,3,prop_func,5)

# Output

Dict{String, Vector{Number}} with 4 entries:
  "Low"   => [9.59361, 9.73523, 10.4781]
  "Close" => [9.98786, 10.4839, 11.0327]
  "Open"  => [10, 9.98786, 10.4839]
  "High"  => [10, 10.4839, 11.0327]

```
"""
function randOHLC(
    base::Number,
    n::Int,
    f::Function,
    precision::Int)

    ohlc=Dict{String,Vector{Number}}(
    "Open"=>[],
    "High"=>[],
    "Low"=>[],
    "Close"=>[])

    lst=base
    while (length(ohlc["Close"])<n)
        arr=randomValue(lst,precision,f)
        sortedarr=sort(arr)
        lst=last(arr)
        push!(ohlc["Open"],first(arr))
        push!(ohlc["High"],last(sortedarr))
        push!(ohlc["Low"],first(sortedarr))
        push!(ohlc["Close"],last(arr))
    end
    return ohlc
end

function populateOHLC(
    asset::Asset,
    prop_func::Function=(x->rand()-0.5);
    start::Number=100,
    precision::Int=10)

    n = length(asset.interval)
    asset.data= randOHLC(start,n,prop_func,precision)
    return asset.data
end


"""
    value(A::Asset,Id::String)

Compute the last value of a given data for the Asset A. 

# Examples

```jldoctest
A=Asset("AAPL",prop_func=x->0);
value(A,"Close")
# output

100
```

"""
value(A::Asset,Id::String="Close")=last(A.data[Id])



"""
    getPrice(asset::Asset, date::Date)

Get the closing price of an asset for a specific date.

# Arguments
- `asset::Asset`: An `Asset` object.
- `date::Date`: The date for which to retrieve the price.

# Returns
- If the price data is available for the specified date, returns the closing price of the asset for that date.
- If the price data is not available for the specified date, returns `nothing`.

"""
function getPrice(asset::Asset, date::Date)::Union{Nothing,Number}
    if haskey(asset.data, "Close")
        dates = keys(asset.data["Close"])
        if date in dates
            return asset.data["Close"][date]
        else
            return nothing
        end
    else
        return nothing
    end
end

simple_average(data::Vector{<:Union{Missing,Number}})=mean(data)

"""
simple_average([1,missing,3,4])

SMA20=IndicatorGenerator(simple_average,20)

x=Asset();
x.data

applyIndicator(SMA20,x,"Close","SMA20")
x.data
"""


function getData(A::Asset,t::Date)::Dict{String,Vector{<:Union{Missing,Number}}}
    res=Dict{String,Vector{<:Union{Missing,Number}}}()
    idx = findfirst(A.interval.==t)
    if (idx !== nothing)
        for (k,v) in A.data
            res[k]=v[1:idx]
        end
    else
        res = A.data
    end
    return res
end


x=Asset();
length(x.data["Close"])
d=Date(2012,1,
findfirst(x.interval.==d)
last(x.interval)
sum(x.interval.==d)
length(getData(x,d)["Close"])
