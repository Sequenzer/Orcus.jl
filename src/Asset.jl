
include("Utils.jl");


#Exports
export 
    Asset,
    randOHLC,
    populateOHLC,
    IndicatorGenerator,
    calculateIndicator,
    applyIndicator,
    value,
    getPrice,
    simple_average,
    getDataUntil,
    RSI,
    plot,
    getIntervals,
    end_date,
    getDomain,
    start_date,
    cutDataUntil!,
    cutDataUntil,
    dataToDefaultOrderedDict





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
    data::Dict{String,AssetData}
    function Asset(
        ticker::String;
        interval::StepRange{Date,<:Period}=Date(2010):Dates.Day(5):Date(2020),
        prop_func::Union{Nothing,Function}=nothing)

        this = new()
        this.ticker = ticker
        if prop_func !== nothing
            populateOHLC(this, interval, prop_func)
        else
            this.data = Dict{String,AssetData}()
            populateOHLC(this)
        end
        return this
    end
    function Asset()
        this = new()
        this.ticker = randstring('A':'Z', 4)
        this.data = Dict{String,AssetData}()
        populateOHLC(this)
        return this
    end
end

Base.show(io::IO,A::Asset) = print(io,"Asset '$(A.ticker)' with $(keys(A.data) |> length) datasets" )



"""
    randOHLC(base::Real,n::Int,precision::Int)

The randOHLC function generates n many OHLC datapoints. The precision argument is the number of random trades the values are based on. 

```jldoctest

Random.seed!(1234)
prop_func=x->rand()-0.5
randOHLC(10,prop_func,Date(2010):Dates.Day(5):Date(2020),5)

# output

Dict{String, Vector{Real}} with 4 entries:
  "Low"   => [9.59361, 9.73523, 10.4781]
  "Close" => [9.98786, 10.4839, 11.0327]
  "Open"  => [10, 9.98786, 10.4839]
  "High"  => [10, 10.4839, 11.0327]

```
"""
function randOHLC(
    base::Real,
    f::Function,
    interval::StepRange{Date,<:Period},
    precision::Int)

    ohlc = Dict{String,AssetData}(
    "Open" => AssetData(missing),
    "High" => AssetData(missing),
    "Low" => AssetData(missing),
    "Close" => AssetData(missing))

    lst = base
    for i in interval
        arr = randomValue(lst, precision, f)
        sortedarr = sort(arr)
        ohlc["Open"][i] = first(arr)
        ohlc["High"][i] = last(sortedarr)
        ohlc["Low"][i] = first(sortedarr)
        ohlc["Close"][i] = last(arr)
        lst = last(arr)
    end
    return ohlc
end

function populateOHLC(
    asset::Asset,
    interval::StepRange{Date,<:Period}=Date(2010):Dates.Day(5):Date(2020),
    prop_func::Function=(x -> rand() - 0.5);
    start::Real=100,
    precision::Int=10)
    asset.data = randOHLC(start, prop_func, interval, precision)

    return asset.data
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
```
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
    data = collect(asset.data[data_key])
    # Initialize the indicator vector with missing data values
    indicator = AssetData(missing)
    # Calculate the indicator for non-empty data points
        for (i,d) in enumerate(data)
            if i > Ind.window
                indicator[d[1]] = Ind.calc_func(map(x->x[2],data)[i-Ind.window+1:i])
            else 
                indicator[d[1]] = missing
            end
        end
    return indicator
end



"""
    applyIndicator(Ind::IndicatorGenerator,asset::Asset,data_key::String,name::String)

# Arguments
- Ind: The IndicatorGenerator we fand to calculate data for.
- asset: The Asset for which the indicator is computed.
- data_key: The key of the data that the indicator is based on.
- name: The name of the indicator.

# Output
The Asset with the indicator added to its data.

"""

function applyIndicator(
    Ind::IndicatorGenerator,
    asset::Asset,
    data_key::String,
    name::String
)
    asset.data[name] = calculateIndicator(Ind, asset, data_key)
    return asset

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
value(A::Asset, Id::String="Close") = last(collect(A.data[Id]))[2]



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
function getPrice(asset::Asset, date::Date)::Union{Nothing,<:Real}
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

"""
simple_average([1,missing,3,4])

SMA20=IndicatorGenerator(simple_average,20)

x=Asset();
x.data

applyIndicator(SMA20,x,"Close","SMA20")
x.data
"""
simple_average(data::IncompleteVector)::Real = mean(skipmissing(data))


"""
    getDataUntil(A::Asset, t::Date)

Get the data of an asset until a specific date.

# Arguments
- `A::Asset`: An `Asset` object.
- `t::Date`: The date until which to retrieve the data.

```jldocteat
Random.seed!(1234);
A=Asset();
d=Dates.Date(2012,1,1);
dt = getDataUntil(A,d)
length(dt["Close"])
# output

147
```
"""
function getDataUntil(A::Asset, t::Date)::Dict{String,AssetData}
    res = Dict{String,AssetData}()
    for (k,v) in A.data
        res[k] = AssetData(missing)
        for (date,value) in v
            if date <= t
                res[k][date] = value
            end
        end
    end
    return res
end

"""
    getDataUntil(A::Asset, t::Int)

Get the first t data points of an asset.

# Example
```jldoctest
Random.seed!(1234);
A=Asset();
dt = getDataUntil(A,10)
length(dt["Close"])
# output

10
```
"""
function getDataUntil(A::Asset, t::Int)::Dict{String,AssetData}
    res = Dict{String,AssetData}()
    for (k,v) in A.data
        res[k] = AssetData(missing)
        for (i,(date,value)) in enumerate(v)
            if i > t
                break
            end
            res[k][date] = value
        end
    end
    return res
end
    
"""
    cutDataUntil!(A::Asset, t::Date)

Cut the data of an asset until a specific date.

```jldoctest
Random.seed!(1234);
A=Asset();
d=Dates.Date(2012,1,1);
cutDataUntil!(A,d)
length(A.data["Close"])
# output

147
```
"""
cutDataUntil!(A::Asset, t::Date) = A.data = getDataUntil(A,t)
cutDataUntil!(A::Asset, t::Int) = A.data = getDataUntil(A,t)




"""

    cutDataUntil(A::Asset, t::Date)

Copy the data of an asset until a specific date.

```jldoctest
Random.seed!(1234);
A=Asset();
d=Dates.Date(2012,1,1);
B = cutDataUntil(A,d)
length(B.data["Close"]) == length(A.data["Close"])

# output

true
```
"""
function cutDataUntil(A::Asset, t::Date)::Asset
    res = Asset(A.ticker)
    res.data = getDataUntil(A,t)
    return res
end

function cutDataUntil(A::Asset, t::Int)::Asset
    res = Asset(A.ticker)
    res.data = getDataUntil(A,t)
    return res
end
    

"""
    RSI(data::IncompleteVector)    

Given a vector of data, calculate the Relative Strength Index of the data.

```jldoctest

RSI([1,missing,2,-3,5])

# output

0.6153846153846154

```
"""
function RSI(data::IncompleteVector)
    delta = diff(data) 
    replace!(delta, missing => 0)
    positive_delta = [ max(0, x) for x in delta]
    negative_delta = [ -min(0, x) for x in delta]
    avg_gain = mean(positive_delta)
    avg_loss = mean(negative_delta)
    RSI = avg_gain / (avg_gain + avg_loss)
    ##Indicator Generator should be independent of Asset.
    return RSI 
end


"""
    RSI(asset::Asset,column::String,window::Int=14)

Given an Asset, calculate the Relative Strength Index of the data in the column.

```jldoctest

Random.seed!(1234);
A=Asset();
RSI(A,"Close",14);
sum(ismissing.(ans))

# output

13
```
"""
function RSI(asset::Asset,column::String="Close",window::Int=14)
    rsi = IndicatorGenerator(RSI,window)   
    applyIndicator(rsi,asset,column,"RSI")
    dt = asset.data
    return dt["RSI"]
end


"""
    plot(A::Asset)

Plot the data of an Asset. # Major ToDo

```jldoctest
A = Asset()
plot(A)


```
"""
function plot(A::Asset, data_key::String="Close")
    println("Plotting Asset: ", A.ticker)
    data = collect(A.data[data_key])
    domain = DateTime[]
    range = Number[]
    for x in data 
        if !ismissing(x[2]) 
            push!(domain, x[1])
            push!(range, x[2])
        end
    end
    lineplot(
        domain,
        range,
        canvas=DotCanvas,
        xlabel="Time",
        ylabel="Value")
end


"""
    getIntervals(A::Asset)

Get the beginning and end dates of the data of an Asset. #ToDo not use random Asset

```jldoctest
Random.seed!(1234);
A=Asset();
getIntervals(A)

# output

(Date(2010-01-01), Date(2019-12-30))
```
"""
function getIntervals(A::Asset)
    isempty(A.data) && return (missing, missing)
    first_key = collect(keys(A.data))[1]

    start_date = first(collect(keys(A.data[first_key])))
    end_date  = last(collect(keys(A.data[first_key])))
    for (_,v) in A.data
        start_date = min(first(collect(keys(v))), start_date)
        end_date = max(last(collect(keys(v))), end_date)
    end
    
    return (start_date, end_date)
end


end_date(A::Asset) = getIntervals(A)[2]
start_date(A::Asset) = getIntervals(A)[1]

Base.length(A::Asset) = end_date(A) - start_date(A)

function getDomain(A::Asset)
    domain = Vector{Dates.Date}()
    for (_,index) in A.data
        for (date,_) in index
            push!(domain,date)
        end
    end
    return sort(unique(domain))
end






"""
    
    DefaultOrderedDict(A::Asset)

Temporary

#Example
```jldoctest
Random.seed!(1234);
A=Asset();
dataToDefaultOrderedDict(A)


```
"""
function dataToDefaultOrderedDict(A::Asset)
    default = Dict{String,Union{<:Real, Missing}}()
    data = AssetSeries(default)
    for (dataset_name,dataset) in A.data
        for (date,value) in dataset
            data[date][dataset_name] = value
        end
    end
    return data
end









