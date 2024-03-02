
import Base: getindex, setindex!, length, show, size


export Asset,
    asset,
    height,
    n_datasets,
    randOHLC,
    calculate_indicator,
    apply_indicator,
    plot,
    plot!,
    value,
    add_datapoint!





"""

This is an Asset

# Fields
- ticker: The name of the Asset, by which it should be identified.
- interval: The maximal interval the data can span across.
- prop_funct: The propability function defining the random walk of the data.

# Example
```jldoctest
x=asset("AAPL")
x.ticker

# output

"AAPL"
```
```
x = asset()
x["Close"]
x["Test"] = x["Close"]
typeof(x["Close"])
x.data
```
```
x.data

x.data_id

```
"""
mutable struct Asset
    ticker::String
    data::DataSeries
    data_id::Vector{String}
    indicator_functions::Vector{Union{Nothing,Tuple{IndicatorGenerator,String}}}
    function Asset(ticker::String,
        data::DataSeries=data_series([DataPoint() for i in 1:4]),
        data_id::Vector{String}=fill("",size(data)[1]))

        @assert size(data)[1] == length(data_id)

        this = new()
        this.ticker = ticker
        this.data = data
        this.data_id = data_id
        this.indicator_functions = fill(nothing, length(data_id))
        return this
    end
end

asset(ticker::String,
      data::DataSeries,
      data_id::Vector{String}) = Asset(ticker, data, data_id)

function asset()
    ticker = randstring('A':'Z', 4)
    ohlc, data_id = randOHLC(100,x->rand()-0.5,1:5:3653,10)
    return Asset(ticker,ohlc,data_id)
end

function asset(ticker::String)
    ohlc, data_id = randOHLC(100,x->rand()-0.5,1:5:3653,10)
    return Asset(ticker,ohlc,data_id)
end


function asset(ticker::String, interval::StepRange{Int,Int}, prop_func::Function, base::Real=100, precision::Int=10)
    ohlc, data_id = randOHLC(base,prop_func,interval,precision)
    return Asset(ticker,ohlc,data_id)
end





Base.show(io::IO,A::Asset) = print(io,"Asset '$(A.ticker)' with $(n_datasets(A)) datasets" )
Base.getindex(A::Asset, key1::Int, key2::Int) = A.data[key1,key2]

function Base.getindex(A::Asset, key::String)
    for (j, id) in enumerate(A.data_id)
        key == id && return A.data[j,:]
    end
    return missing
end

function Base.setindex!(A::Asset, dp::DataPoint, key1::String) 
    index = findfirst(x->x==key1,A.data_id)
    if isnothing(index)
        @assert length(dp) == size(A.data)[2]
        A.data_id = push!(A.data_id,key1)
        A.data = vcat(A.data,transpose(dp))
    else
        A[index,:] = dp
    end
    return A 
end 

function Base.setindex!(A::Asset, dp::DataPoint, key1::Int, ::Colon) 
    @assert length(dp) == size(A.data)[2]
    @assert key1 <= size(A.data)[1]

    A.data[key1,:] = dp
    return A 
end

Base.length(A::Asset) = size(A.data)[2]
height(A::Asset) = size(A.data)[1]
n_datasets(A::Asset) = height(A)
Base.size(A::Asset) = size(A.data)

"""
    randOHLC(base::Real,n::Int,precision::Int)

The randOHLC function generates n many OHLC datapoints. The precision argument is the number of random trades the values are based on. 

```jldoctest

Random.seed!(1234)
prop_func=x->rand()-0.5
randOHLC(10,prop_func,1:2:5,5)

# output

julia> randOHLC(10,prop_func,1:2:5,5)
4×5 Matrix{Union{Missing, Number}}:
 10        missing   9.98786  missing  10.4839
 10        missing  10.4839   missing  11.0327
  9.59361  missing   9.73523  missing  10.4781
  9.98786  missing  10.4839   missing  11.0327

```
"""
function randOHLC(
    base::Number,
    f::Function,
    interval::StepRange{Int,Int},
    precision::Int)
    
    # Warning! if 1:2:4 is used, the length of the interval is 2, not 3
    full_interval = interval.start:1:interval.stop

    data_id = ["Open","High","Low","Close"]
    ohlc = DataSeries(fill(missing,(length(data_id),length(full_interval))))

    lst = base
    for i in full_interval
        if rem(i-1 ,step(interval)) !== 0
            foreach(j->ohlc[j,i]=missing,1:length(data_id))
            continue
        end
        arr = randomValue(lst, precision, f)
        sortedarr = sort(arr)
        ohlc[1,i] = first(arr)
        ohlc[2,i] = last(sortedarr)
        ohlc[3,i] = first(sortedarr)
        ohlc[4,i] = last(arr)
        lst = last(arr)
    end
    return ohlc, data_id
end

"""
    plot(A::Asset)

Plot the data of an Asset. # Major ToDo

```jldoctest
A = asset()
p = plot(A)
B = asset()
plot!(p,B)

```
"""
function plot(A::Asset, data_key::String="Close")
    println("Plotting Asset: ", A.ticker)
    range = collect(skipmissing(A[data_key]))
    domain = 1:length(range)
    return lineplot(
        domain,
        range,
        xlabel="Time",
        ylabel="Value",
        title="$(A.ticker) $(data_key) data"
        )
end


# Should be reworked 
function plot!(plt::UnicodePlots.Plot{<:UnicodePlots.Canvas}, A::Asset, data_key::String="Close")
    println("Plotting Asset: ", A.ticker)
    range = collect(skipmissing(A[data_key]))
    domain = 1:length(range)
    return lineplot!(
        plt,
        domain,
        range
        )
end

"""
    calculateIndicator(Ind::IndicatorGenerator,a::Asset,data_key::String)

# Arguments
- Ind: The IndicatorGenerator we fand to calculate data for.
- asset: The Asset for which the indicator is computed.
- data_key: The key of the data that the indicator is based on.    

# Output
An Array of the Data calculated.

```jldoctest
Random.seed!(1234)
x=asset()
SMA10=indicator_generator(simple_average,10)
calculate_indicator(SMA10,x,"Close")

```
"""
function calculate_indicator(Ind::IndicatorGenerator, asset::Asset, data_key::String)
    @assert !isnothing(findfirst(x->x==data_key,asset.data_id))

    data = asset[data_key]
    # Initialize the indicator vector with missing data values
    indicator = DataPoint(fill(missing, length(data)))
    # Calculate the indicator for non-empty data points
        for i in eachindex(data)
            if i > Ind.window
                indicator[i] = Ind.calc_func(data[i-Ind.window+1:i])
            else 
                indicator[i] = missing
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
```jldoctest
Random.seed!(1234)
SMA20=IndicatorGenerator(simple_average,20)

x=asset();
apply_indicator(SMA20,x,"Close","SMA20")
height(x)

# output


```
"""

function apply_indicator(
    Ind::IndicatorGenerator,
    asset::Asset,
    data_key::String,
    name::String
)
    asset[name] = calculate_indicator(Ind, asset, data_key)
    i = findfirst(x->x==name,asset.data_id) 
    if i > length(asset.indicator_functions)
        push!(asset.indicator_functions,(Ind,data_key))
    else
        asset.indicator_functions[i] = (Ind,data_key)
    end
    return asset

end

"""
    add_datapoint!(A::Asset, dp::DataPoint)

```jldoctest
Random.seed!(1234)
SMA20=IndicatorGenerator(simple_average,20)
x=asset();
apply_indicator(SMA20,x,"Close","SMA20")
x.data
x.indicator_functions
x.data_id
add_datapoint!(x,DataPoint([113,113,113,113,missing]))
```
"""
function add_datapoint!(A::Asset, dp::DataPoint)
    @assert length(dp) == height(A)
    for i in eachindex(A.data_id)
        @assert (isnothing(A.indicator_functions[i]) || ismissing(dp[i])) # !A || B == A => B
        @assert (ismissing(dp[i]) || isnothing(A.indicator_functions[i]))
     end
    # Calculate the indicator for non-empty data points
    for i in eachindex(A.indicator_functions)
        if !isnothing(A.indicator_functions[i])
            Ind, name = A.indicator_functions[i]
            j = findfirst(x->x==name,A.data_id)
            dp[i] = Ind.calc_func(A.data[j,end-Ind.window+1:end])
        end
    end 

    A.data = hcat(A.data,dp)

end
"""
    value(A::Asset, data_key::String="Close")

```jldoctest
Random.seed!(1234)
x=asset()
value(x,"Close")

# output
110.21778063564074
```
"""
function value(A::Asset, data_key::String="Close")
    @assert length(A) > 0 "The Asset has no data"
    first(Iterators.reverse((skipmissing(A[data_key]))))
end



