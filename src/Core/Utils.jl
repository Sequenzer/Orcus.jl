#Exports
export AssetData,
    AssetSeries,
    randomValue,
    DataSeries,
    DataPoint,
    data_series,
    data_point,
    add!




IncompleteVector = AbstractVector{<:Union{<:Real, Missing}}


"""
    AssetData(default::Union{<:Real, Missing}=missing)


A struct that holds a Dict of Dates and Real values. The default value is Missing.

# Example
```jldoctests
asset = AssetData(missing)
date = Dates.Date(2019,1,1)
asset[date]
length(asset)

#output

missing
```
"""
AssetData = DefaultOrderedDict{DateTime, Union{<:Real, Missing}}


"""

    AssetSeries(default::Union{<:Real, Missing}=missing)

A struct that holds a Dict of Dates and Dicts of Strings and Real values. The default value is Missing.

# Example
```jldoctests
default = Dict{String,Union{<:Real, Missing}}("Close"=>missing,"Open"=>missing)
asset = AssetSeries(default)
date = Dates.Date(2019,1,1)
asset[date]

#output

Dict{String, Union{Missing, Real}} with 2 entries:
  "Close" => missing
  "Open"  => missing

```
"""
AssetSeries = DefaultOrderedDict{DateTime, Dict{String, Union{<:Real, Missing}}}



"""
    randomValue(x::Real,n::Int,prop_func::Function)

Generates a Vector of n random values around x based on a propability function.

# Example
```jldoctests
x=100;
n=3;
f=k->k;
randomValue(x,n,f)

# output
[100,200,400]
```
"""
function randomValue(x::Real,n::Int,f::Function)
    arr::Vector{Real}=[x]
    while (length(arr)<n)
        old = last(arr)
        push!(arr,old+f(old))
    end
    return arr
end


"""
    DataSeries = Vector{ Union{ DataPoint, Missing}}

A struct that holds a Vector of DataPoints. The DataPoint is a Vector of Union{<:Number, Missing}.

```jldoctests
dp1 = DataPoint([1,2,missing,4,5])
dp2 = DataPoint([1,2,missing,4,missing,missing])
dp3 = DataPoint([1,2,3,4,5,6,7])
dp4 = DataPoint([1])

ds = data_series([dp1,missing,dp2])
add!(ds,dp3;start = 3)
add!(ds,dp4)

"""
DataPoint = Vector{ Union{<:Number, Missing}}

DataSeries = Matrix{ Union{ <:Number, Missing}}

function data_series(x::Vector{<:Union{DataPoint, Missing}})
    hght = maximum([length(i) for i in x if !ismissing(i)])
    lgth = length(x)
    arr = DataSeries(fill(missing, (lgth, hght)))
    for i in eachindex(x)
        ismissing(x[i]) && continue
        for j in eachindex(x[i])
            arr[i,j] = x[i][j]
        end
    end
    return arr
end

function data_point(x::Vector{<:Union{<:Number, Missing}})
    return DataPoint(x)
end

data_point(n::Int) = DataPoint(fill(missing, n))

function add!(x::DataSeries, y::DataPoint; start=1)
    n = size(x)[2]
    new_n = max(n, length(y)+start-1)
    new_x  = DataSeries(fill(missing, (size(x)[1], new_n)))
    #fill rows with missing
    for i in 1:size(x)[1]
      new_x[i, 1:new_n] .= missing
      new_x[i, 1:n] = x[i, :]
    end
    new_y = data_point(fill(missing, new_n))
    new_y[start:length(y)+start-1] = y
    println(new_y)
    new_x = vcat(new_x, transpose(new_y))
    #fill start of y with missing
    x = new_x
    return x
end

