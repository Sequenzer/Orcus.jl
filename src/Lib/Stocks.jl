#Binding for the stocks in ./data/(name).csv

export load_stock, load_stocks, available_stocks, AAPL, GOOG

"""
    load_stock(name::String)

    Load the stock data from the csv file in the data folder

```julia
load_stock("GOOG")

```
"""
const _STOCKS_DATA_DIR = joinpath(@__DIR__, "data")

function load_stock(name::String)
    dt = CSV.File(joinpath(_STOCKS_DATA_DIR, "$(name).csv"))
    return asset(dt, name)
end


function to_index(v::Vector{Dates.Date})
    if issorted(v)
      mi = Dates.value(v[1])
    elseif issorted(v,rev=true)
      return to_index(reverse(v))
    else
      return to_index(sort!(v))
    end

    return [Dates.value(d)-mi+1 for d in v]
end




function asset(fl::CSV.File, name::String="Asset")
    @assert hasproperty(fl, :date) "The CSV file must have a date column"
    index = to_index(fl[:date])
    nms   = filter(x -> x !== :date, propertynames(fl))
    data  = DataPoint[]

    for n in nms
        v  = fill(NaN, index[end])      # NaN = no data for this bar
        dt = reverse(fl[n])
        for i in 1:length(fl[:date])
            v[index[i]] = Float64(dt[i])
        end
        push!(data, v)
    end
    return asset(name, data_series(data), uppercasefirst.(String.(nms)))
end

"""
    available_stocks() -> Vector{String}

List all stock tickers available in the data directory.
"""
available_stocks() = sort([splitext(f)[1]
    for f in readdir(_STOCKS_DATA_DIR) if endswith(f, ".csv")])

"""
    load_stocks(names::Vector{String}) -> Market

Load multiple stocks by ticker name and return them as a Market.
All tickers must exist in the data directory (see `available_stocks()`).
"""
function load_stocks(names::Vector{String})
    market([load_stock(n) for n in names])
end

AAPL = load_stock("AAPL")
GOOG = load_stock("GOOG")



