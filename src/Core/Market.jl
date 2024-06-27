

export Market,
       market,
       addAsset!,
       addAssets!,
       assets,
       start_date,
       to_asset,      
       end_date,
       names

"""
    Market

A structure comprised of all Assets

# Example

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
isa(M,Market)
# output

true
```
"""
mutable struct Market 
    data::Dict{String,Asset}
    function Market(assets::Vector{Asset})
        this = new()
        this.data = Dict{String,Asset}()
        foreach(x->this.data[x.ticker]=x,assets)
        return this
    end
    Market(asset::Asset) = Market([asset])
    Market() = new(Dict{String,Asset}())
end


market(assets::Vector{Asset}) = Market(assets)
market() = market(Asset[])
market(asset::Asset) = market([asset])

"""
    market(n_Assets::Int)

Create a Market with n_Assets Assets

# Example

```jldoctest
Random.seed!(1234);
M=market(3);
length(M.data)
# output

3
```
"""
market(n_Assets::Int) = Market([asset() for i in 1:n_Assets])

function Base.show(io::IO,M::Market) 
    print(io,"Market with $(length(M.data)) Assets: \n") 
    for (k,v) in M.data
        println(join(fill(" ", 1)) * "$(repr(k)) => $(repr(v))")
    end
end

Base.getindex(M::Market,ticker::String) = M.data[ticker]
Base.getindex(M::Market, i::Int) = values(M.data)[i]

assets(M::Market) = values(M.data)


"""
# Example

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
isa(M,Market)
# output

true
```
"""
Base.names(M::Market) = keys(M.data)


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

```jldoctest
Random.seed!(1234);
M=market(Asset[]);
addAssets!(M,[asset(),asset()])
length(M.data)

# output
2
```
"""
function addAssets!(M::Market,assets::AbstractVector{Asset})
    foreach(x->M.data[x.ticker]=x,assets) 
end


Base.size(M::Market) = (height(M),length(M))
Base.length(M::Market) = max(length.(values(M.data))...) #This should change
height(M::Market) = length(M.data)

Base.getindex(M::Market, key2::Int, ::Colon) = to_asset(M)[key2,:]
Base.getindex(M::Market, key1::Int, key2::Int) = to_asset(M)[key1,key2]
Base.getindex(M::Market, ::Colon, key2::Int) = to_asset(M)[:,key2]
## Untested broken functions!!!:
"""

    cutDataUntil(M::Market,length::Int)

Cut the data of all Assets in the Market until a certain length

# Example
```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
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


function to_asset(M::Market)
    @assert length(unique(names(M))) == length(names(M))
    ats = assets(M) 
    len = maximum(length.(ats))
    dt = DataSeries(undef,0,len)
    namesToAdd = String[]
    for (k,v) in M.data
        dt = vcat(dt,v.data)
        append!(namesToAdd, k * "_" .* names(v))
        
    end
    return asset("Market",dt,namesToAdd) 
end


