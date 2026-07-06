#Binding for the stocks in ./data/(name).csv

export load_stock, load_stocks, available_stocks, AAPL, GOOG

const _STOCKS_DATA_DIR = joinpath(@__DIR__, "data")

"""
    load_stock(name::String)

Load the stock data from the CSV file `data/<name>.csv`.

```julia
load_stock("GOOG")
```
"""
function load_stock(name::String)
  dt = read_stock_csv(joinpath(_STOCKS_DATA_DIR, "$(name).csv"))
  return asset(dt, name)
end

# Minimal reader for the sample stock CSVs: a header row of column names followed by
# comma-separated rows. The `date` column is parsed as `Date`, every other column as
# `Float64`. Returns a `NamedTuple` of columns so downstream code can use `nt[:date]`,
# `propertynames(nt)`, and `hasproperty`. Avoids a CSV.jl dependency for the few fixtures
# we ship; it is not a general-purpose CSV parser (no quoting, no embedded commas).
function read_stock_csv(path::String)
  lines = readlines(path)
  isempty(lines) && error("empty CSV file: $path")
  header = Symbol.(split(lines[1], ','))
  cols = [Vector{String}() for _ in header]
  for ln in @view lines[2:end]
    isempty(ln) && continue
    fields = split(ln, ',')
    length(fields) == length(header) ||
      error("malformed row in $path: $ln")
    for (c, f) in zip(cols, fields)
      push!(c, f)
    end
  end
  parsed = map(header, cols) do name, col
    name === :date ? parse.(Date, col) : parse.(Float64, col)
  end
  return NamedTuple{Tuple(header)}(Tuple(parsed))
end

function to_index(v::Vector{Dates.Date})
  if issorted(v)
    mi = Dates.value(v[1])
  elseif issorted(v; rev=true)
    return to_index(reverse(v))
  else
    return to_index(sort!(v))
  end

  return [Dates.value(d) - mi + 1 for d in v]
end

function asset(fl::NamedTuple, name::String="Asset")
  @assert hasproperty(fl, :date) "The CSV file must have a date column"
  index = to_index(fl[:date])
  nms = collect(filter(x -> x !== :date, propertynames(fl)))
  data = DataPoint[]

  for n in nms
    v = fill(NaN, index[end])      # NaN = no data for this bar
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

Load multiple stocks onto a shared bar grid — the sorted union of all trading dates —
and attach it as the market's time axis. Dates missing for a ticker are NaN bars.
All tickers must exist in the data directory (see `available_stocks()`).
"""
function load_stocks(names::Vector{String})
  nts = [read_stock_csv(joinpath(_STOCKS_DATA_DIR, "$(n).csv")) for n in names]
  grid = sort!(unique(reduce(vcat, [nt.date for nt in nts])))
  pos = Dict(d => j for (j, d) in enumerate(grid))
  M = market()
  for (name, nt) in zip(names, nts)
    cols = collect(filter(x -> x !== :date, propertynames(nt)))
    data = fill(NaN, length(cols), length(grid))
    for (r, c) in enumerate(cols)
      vals = nt[c]
      for (i, d) in enumerate(nt.date)
        data[r, pos[d]] = vals[i]
      end
    end
    add_asset!(M, Asset(name, data, uppercasefirst.(String.(cols))))
  end
  set_axis!(M, grid)
  return M
end

# Shared, mutable sample fixtures. A backtest's `init` can mutate an Asset in place
# (e.g. `apply_indicator` grows `asset.data`), so do NOT run strategies directly against
# these — wrap a copy: `market([copy(AAPL)])`. `batch_backtest` copies the market per job,
# so sweeps over these are safe. `const` here is for binding type-stability, not immutability
# of the underlying Asset.
const AAPL = load_stock("AAPL")
const GOOG = load_stock("GOOG")
