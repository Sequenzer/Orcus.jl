#Binding for the stocks in ./data/(name).csv

export load_stock,AAPL,GOOG

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

  data = DataPoint[]

  names = filter(x -> x!==:date,propertynames(fl))

  for n in names
    v = DataPoint(fill(missing, index[end]))
    dt = reverse(fl[n])
    for i in 1:length(fl[:date])
      v[index[i]] = dt[i]
    end
    push!(data, DataPoint(v))
  end
  return asset(name, data_series(data), uppercasefirst.(String.(names)))
end

AAPL = load_stock("AAPL")
GOOG = load_stock("GOOG")



