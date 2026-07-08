#Binding for the stocks in ./data/(name).csv

const _STOCKS_DATA_DIR = joinpath(@__DIR__, "data")

"""
    load_stock(name::String)

Load the stock data from the CSV file `data/<name>.csv`.

```jldoctest
load_stock("GOOG")
# output

Asset 'GOOG' with 6 datasets
```
"""
function load_stock(name::String)
  return load_csv(joinpath(_STOCKS_DATA_DIR, "$(name).csv"); ticker=name)
end

function read_stock_csv(path::String; date_col::Symbol=:date)
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
    name === date_col ? parse.(Date, col) : parse.(Float64, col)
  end
  return NamedTuple{Tuple(header)}(Tuple(parsed))
end

function _rename_columns(nt::NamedTuple, date::Symbol, columns::Dict{Symbol,Symbol})
  names = Symbol[:date]
  vals = Any[nt[date]]
  for name in propertynames(nt)
    name === date && continue
    push!(names, get(columns, name, name))
    push!(vals, nt[name])
  end
  return NamedTuple{Tuple(names)}(Tuple(vals))
end

"""
    load_csv(path::String; ticker::String=splitext(basename(path))[1], date::Symbol=:date, columns::Dict{Symbol,Symbol}=Dict{Symbol,Symbol}())

Load an OHLC CSV from an arbitrary file path. `date` names the source date column; `columns`
maps source header names to Orcus's canonical names (`:open`/`:high`/`:low`/`:close`/`:volume`),
e.g. `columns=Dict(:adjclose => :close)` for a Yahoo-style export. `ticker` defaults to the
filename stem.

```jldoctest
path=joinpath(pkgdir(Orcus), "src", "Lib", "data", "GOOG.csv");
load_csv(path)
# output

Asset 'GOOG' with 6 datasets
```
"""
function load_csv(path::String; ticker::String=splitext(basename(path))[1],
  date::Symbol=:date, columns::Dict{Symbol,Symbol}=Dict{Symbol,Symbol}())
  nt = _rename_columns(read_stock_csv(path; date_col=date), date, columns)
  return asset(nt, ticker)
end

# Dense bar index (1 = earliest date) for an *ascending* date vector.
to_index(v::Vector{Dates.Date}) = [Dates.value(d) - Dates.value(minimum(v)) + 1 for d in v]

function asset(fl::NamedTuple, name::String="Asset")
  @assert hasproperty(fl, :date) "The CSV file must have a date column"
  perm = sortperm(fl[:date])       # accept any row order (ascending, descending, unsorted)
  dates = fl[:date][perm]
  index = to_index(dates)
  nms = collect(filter(x -> x !== :date, propertynames(fl)))
  data = DataPoint[]

  for n in nms
    v = fill(NaN, index[end])      # NaN = no data for this bar
    col = fl[n][perm]
    for i in eachindex(dates)
      v[index[i]] = Float64(col[i])
    end
    push!(data, v)
  end
  return asset(name, data_series(data), uppercasefirst.(String.(nms)))
end

"""
    available_stocks()

List all stock tickers available in the data directory.

```jldoctest
length(available_stocks())
# output

34
```
"""
available_stocks() = sort([splitext(f)[1] for f in readdir(_STOCKS_DATA_DIR) if endswith(f, ".csv")])

"""
    load_csvs(paths::Vector{String}; tickers::Vector{String}=[splitext(basename(p))[1] for p in paths], date::Symbol=:date, columns::Dict{Symbol,Symbol}=Dict{Symbol,Symbol}())

Load multiple OHLC CSVs from arbitrary file paths onto a shared bar grid and
attach it as the market's time axis. Dates missing for a ticker are NaN bars.
`tickers` defaults to each path's filename stem; `date`/`columns` are shared
across all paths (see [`load_csv`](@ref)).

```jldoctest
dir=joinpath(pkgdir(Orcus), "src", "Lib", "data");
M=load_csvs([joinpath(dir, "AAPL.csv"), joinpath(dir, "GOOG.csv")]);
length(M.data)
# output

2
```
"""
function load_csvs(paths::Vector{String};
  tickers::Vector{String}=[splitext(basename(p))[1] for p in paths],
  date::Symbol=:date, columns::Dict{Symbol,Symbol}=Dict{Symbol,Symbol}())
  nts = [_rename_columns(read_stock_csv(p; date_col=date), date, columns) for p in paths]
  grid = sort!(unique(reduce(vcat, [nt.date for nt in nts])))
  pos = Dict(d => j for (j, d) in enumerate(grid))
  M = market()
  for (name, nt) in zip(tickers, nts)
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

"""
    load_stocks(names::Vector{String})

Load multiple stocks onto a shared bar grid and attach it as the market's time
axis. Dates missing for a ticker are NaN bars. All tickers must exist in the
data directory (see [`available_stocks`](@ref)).

```jldoctest
M=load_stocks(["AAPL","GOOG"]);
length(M.data)
# output

2
```
"""
function load_stocks(names::Vector{String})
  return load_csvs([joinpath(_STOCKS_DATA_DIR, "$(n).csv") for n in names]; tickers=names)
end

# Shared, mutable sample fixtures. A backtest's `init` can mutate an Asset in place
# (e.g. `apply_indicator` grows `asset.data`), so do NOT run strategies directly against
# these — wrap a copy: `market([copy(AAPL)])`. `batch_backtest` copies the market per job,
# so sweeps over these are safe. `const` here is for binding type-stability, not immutability
# of the underlying Asset.

"""
    AAPL

Shared sample `Asset` fixture loaded from `data/AAPL.csv`. Wrap a copy before running a
strategy against it: `market([copy(AAPL)])`.
"""
const AAPL = load_stock("AAPL")

"""
    GOOG

Shared sample `Asset` fixture loaded from `data/GOOG.csv`. Wrap a copy before running a
strategy against it: `market([copy(GOOG)])`.
"""
const GOOG = load_stock("GOOG")
