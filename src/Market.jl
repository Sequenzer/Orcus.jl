#Exports
export Market
export addAsset!
export addAssets!




"""
    Market

A structure comprised of all Assets

# Example

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=Market([x,y]);
isa(M,Market)
# output

true
```
"""
mutable struct Market 
    data::Dict{String,Asset}
    interval::StepRange{Date,<:Period}
    function Market(assets::Vector{Asset})
        this = new()
        this.data = Dict{String,Asset}()
        foreach(x->this.data[x.ticker]=x,assets)
        return this
    end
    Market(asset::Asset) = Market([asset])
    Market() = new(Dict{String,Asset}())
end

"""
    Market(n_Assets::Int)

Create a Market with n_Assets Assets

# Example

```jldoctest
Random.seed!(1234);
M=Market(3);
length(M.data)
# output

3
```
"""
Market(n_Assets::Int) = Market([asset() for i in 1:n_Assets])

function Base.show(io::IO,M::Market) 
    print(io,"Market with $(length(M.data)) Assets: \n") 
    for (k,v) in M.data
        println(join(fill(" ", 1)) * "$(repr(k)) => $(repr(v))")
    end
end

Base.getindex(M::Market,ticker::String) = M.data[ticker]



"""
    addAsset!(M::Market,Asset::Asset)

Add an  Assets to the Market

# Example 

M=Market(Asset[]);
addAsset!(M,asset())
M.data
"""
function addAsset!(M::Market,A::Asset)
    M.data[A.ticker]=A
end
"""
    addAssets!(M::Market,Assets::AbstractVector{Asset})

Add a Vector of Assets to the Market

# Example 

M=Market(Asset[]);
addAssets!(M,[Asset(),Asset()])
"""
function addAssets!(M::Market,assets::AbstractVector{Asset})
    foreach(x->M.data[x.ticker]=x,assets) 
end


Base.size(M::Market) = length(M.data)



start_date(M::Market) = minimum(start_date.(values(M.data)))
end_date(M::Market) = maximum(end_date.(values(M.data)))
Base.length(M::Market) = max(length.(values(M.data))...) #This should change


"""
    cutDataUntil!(M::Market,date::Date)

Cut the data of all Assets in the Market until a certain date

# Example
```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
cutDataUntil!(M,Dates.Date(2020,1,3))

# output



```
"""
function cutDataUntil!(M::Market,date::DateTime)
    foreach(x->cutDataUntil!(x,date),values(M.data))
end

"""
    cutDataUntil(M::Market,date::Date)

Cut the data of all Assets in the Market until a certain date

# Example
```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
M2=cutDataUntil(M,Dates.DateTime(2015,1,3))
M3=cutDataUntil(M,start_date(M))
length(M3)

# output
1825
```
"""

function cutDataUntil(M::Market,date::DateTime)
    newMarket=Market()
    for (k,v) in M.data
        newMarket.data[k]=cutDataUntil(v,date)
    end
    return newMarket
end

"""

    cutDataUntil(M::Market,length::Int)

Cut the data of all Assets in the Market until a certain length

# Example
```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
M2=cutDataUntil(M,100)
length(M2) 

# output
Dates.Day(495)
```
"""
function cutDataUntil(M::Market,length::Int)
    newMarket=Market()
    for (k,v) in M.data
        newMarket.data[k]=cutDataUntil(v,length)
    end
    return newMarket
end




function takeData!(source::Market,target::Market,date::DateTime)
    for (k,v) in target.data
        if haskey(source.data,k)
            takeData!(source.data[k],v,date)
        end
    end
end
function takeData!(source::Market,target::Market,length::Int)
    for (k,v) in target.data
        if haskey(source.data,k)
            takeData!(source.data[k],v,length)
        end
    end
end
    


    
function getDomain(M::Market)
    domain = Vector{DateTime}() 
    for (_,v) in M.data
        append!(domain,getDomain(v))
    end
    
    return sort(unique(domain))
end





