



include("src/Asset.jl");

mutable struct Market 
    data::Dict{String,Asset}
    function Market(assets::Array{Asset})
        this = new()
        this.data = Dict{String,Asset}()
        foreach(x->this.data[x.ticker]=x,assets)
        return this
    end
end

function addAsset!(A::Asset,M::Market)
    M.data[Asset.ticker]=A
end







##Tests
x=Asset("AAPL")
populate_ohlc(x)
    
y=Asset("GOOG")
populate_ohlc(y)

m=Market([x,y])
