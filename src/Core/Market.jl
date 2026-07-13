
"""
    Market

A collection of Assets keyed by ticker. Carries an optional shared time axis: `axis[j]`
labels bar `j` of every asset; `nothing` means bars are abstract integer indices.

```jldoctest
Random.seed!(1);
M=market([asset(),asset()]);
length(M.data)
# output

2
```
"""
mutable struct Market
  data::Dict{String,Asset}
  assets::Vector{Asset}        # same Assets as `data`, contiguous for hash-free hot-path iteration
  _length::Int
  axis::Union{Nothing,Vector{DateTime}}
  fx_registry::Dict{Symbol,String}   # currency → ticker of its rate asset (see set_fx!)
  fx_wired::Vector{Tuple{Asset,Asset}}   # (asset, rate asset) pairs; empty = no per-bar fx work

  function Market(assets::Vector{Asset})
    this = new()
    this.data = Dict{String,Asset}()
    this.assets = Asset[]
    this._length = 0
    this.axis = nothing
    this.fx_registry = Dict{Symbol,String}()
    this.fx_wired = Tuple{Asset,Asset}[]
    for a in assets
      add_asset!(this, a)
    end
    return this
  end
  Market(asset::Asset) = Market([asset])
  Market() = new(
    Dict{String,Asset}(), Asset[], 0, nothing, Dict{Symbol,String}(), Tuple{Asset,Asset}[]
  )
end

"""
    market(assets::Vector{Asset})
    market(asset::Asset)
    market(n_assets::Int)
    market()
Construct a new Market from the given assets, a single asset, or an empty market. The
`n_assets` constructor creates `n_assets` random assets with default parameters.

```jldoctest
Random.seed!(1);
M=market([asset(),asset()]);
length(M.data)
# output

2
```
"""
market(assets::Vector{Asset}) = Market(assets)
market() = market(Asset[])
market(asset::Asset) = market([asset])
market(n_assets::Int) = Market([asset() for i in 1:n_assets])

function Base.show(io::IO, M::Market)
  print(io, "Market with $(length(M.data)) Assets: \n")
  for (k, v) in M.data
    println(join(fill(" ", 1)) * "$(repr(k)) => $(repr(v))")
  end
end

Base.getindex(M::Market, ticker::String) = M.data[ticker]
Base.getindex(M::Market, i::Int) = values(M.data)[i]

assets(M::Market) = values(M.data)

Base.length(M::Market) = M._length       # O(1) — cached

"""
    height(M::Market)

Number of assets in the market.

```jldoctest
Random.seed!(1);
M=market([asset(),asset()]);
height(M)
# output

2
```
"""
height(M::Market) = length(M.data)
Base.size(M::Market) = (height(M), length(M))
Base.names(M::Market) = keys(M.data)

"""
    add_asset!(M::Market, A::Asset)

Add or replace an asset in the market, keyed by its ticker.

```jldoctest
M=market();
add_asset!(M, asset("AAPL"));
length(M.data)
# output

1
```
"""
function add_asset!(M::Market, A::Asset)
  if haskey(M.data, A.ticker)                     # replacing: keep the vector in sync, no dup
    old = M.data[A.ticker]
    idx = findfirst(===(old), M.assets)
    idx === nothing ? push!(M.assets, A) : (M.assets[idx] = A)
  else
    push!(M.assets, A)
  end
  M.data[A.ticker] = A
  M._length = max(M._length, length(A))
  if haskey(M.fx_registry, A.currency) || A.ticker in values(M.fx_registry)
    _rebuild_fx_wiring!(M)
  end
  return M
end

function _rebuild_fx_wiring!(M::Market)
  empty!(M.fx_wired)
  for (ccy, tk) in M.fx_registry
    fx = get(M.data, tk, nothing)
    fx === nothing && continue
    for a in M.assets
      if a.currency === ccy
        a.fx = fx
        a.fx_rate = _fx_rate_of(fx, a.fx_rate)
        push!(M.fx_wired, (a, fx))
      end
    end
  end
  return M
end

function add_assets!(M::Market, assets::AbstractVector{Asset})
  for a in assets
    add_asset!(M, a)
  end
end

Base.getindex(M::Market, key2::Int, ::Colon) = to_asset(M)[key2, :]
Base.getindex(M::Market, key1::Int, key2::Int) = to_asset(M)[key1, key2]
Base.getindex(M::Market, ::Colon, key2::Int) = to_asset(M)[:, key2]

_rewire_fx!(M::Market) = _rebuild_fx_wiring!(M)

function Base.copy(M::Market)
  M2 = Market([copy(A) for A in values(M.data)])
  M2.axis = M.axis === nothing ? nothing : copy(M.axis)
  M2.fx_registry = copy(M.fx_registry)
  return _rewire_fx!(M2)
end

function Base.getindex(M::Market, r::UnitRange{Int})
  newM = Market(Asset[])
  for (_, v) in M.data
    add_asset!(newM, v[r])
  end
  M.axis === nothing || (newM.axis = M.axis[r])
  newM.fx_registry = copy(M.fx_registry)
  return _rewire_fx!(newM)
end

"""
    shorten!(M::Market, U::UnitRange{Int})

Trim every asset in the market to the given column range.

```jldoctest
Random.seed!(1);
M=market([asset(),asset()]);
shorten!(M, 1:10);
length(M)
# output

10
```
"""
function shorten!(M::Market, U::UnitRange{Int})
  for (_, v) in M.data
    shorten!(v, U)
  end
  M.axis === nothing || (M.axis = M.axis[U])
  M._length = length(U)
end

function to_asset(M::Market)
  @assert length(unique(names(M))) == length(names(M))
  ats = assets(M)
  len = maximum(length.(ats))
  dt = DataSeries(undef, 0, len)
  namesToAdd = String[]
  for (k, v) in M.data
    dt = vcat(dt, Matrix{Float64}(v.data))
    append!(namesToAdd, k * "_" .* names(v))
  end
  return asset("Market", dt, namesToAdd)
end

function to_market(A::Asset)
  M = market()
  nms = split.(names(A), "_")
  return nms
end

"""
    advance_to!(M::Market, i::Int)

Reveal bars `1:i` of every asset in the market — what the backtest loop does once per bar.

```jldoctest
Random.seed!(1);
M=market([asset(),asset()]);
advance_to!(M, 5);
length(M)
# output

5
```
"""
@inline function advance_to!(M::Market, i::Int)
  max_len = 0
  @inbounds for a in M.assets        # contiguous Vector — no Dict hashing per bar
    a.visible = min(i, size(a.data, 2))
    max_len = max(max_len, a.visible)
  end
  M._length = max_len
  # After every cursor has moved: refresh cached rates for fx-wired assets only.
  # Single-currency markets pay one empty-vector length check.
  @inbounds for (a, f) in M.fx_wired
    a.fx_rate = _fx_rate_of(f, a.fx_rate)
  end
  return M
end

"""
    set_data_to!(M, N, u)

Back-compat shim for the old view-based API: advances `M` to reveal bars `1:last(u)` via the
`visible` cursor (`M` already holds the full series). `N` is ignored. Prefer [`advance_to!`](@ref).

```jldoctest
Random.seed!(1);
M=market([asset(),asset()]);
Orcus.set_data_to!(M, M, 1:3);
length(M)
# output

3
```
"""
set_data_to!(M::Market, N::Market, u::UnitRange{Int}) = advance_to!(M, last(u))

"""
    set_axis!(M::Market, axis::Vector{DateTime})

Attach a shared time axis: `axis[j]` labels bar `j` of every asset. Must be sorted and
match the full data width of the market's widest asset.

```jldoctest
using Dates;
Random.seed!(1);
M=market([asset("AAPL")]);
axis=DateTime(2000,1,1) .+ Day.(0:3650);
set_axis!(M, axis);
has_axis(M)
# output

true
```
"""
function set_axis!(M::Market, axis::Vector{DateTime})
  @assert issorted(axis) "axis must be sorted ascending"
  width = maximum(a -> size(a.data, 2), M.assets; init=0)
  @assert length(axis) == width "axis length $(length(axis)) != market data width $width"
  M.axis = axis
  return M
end
set_axis!(M::Market, axis::Vector{Date}) = set_axis!(M, DateTime.(axis))

"""
    has_axis(M::Market)

Whether the market has a shared time axis attached.

```jldoctest
M=market([asset("AAPL")]);
has_axis(M)
# output

false
```
"""
has_axis(M::Market) = M.axis !== nothing

"""
    set_fx!(M::Market, ccy::Symbol, fx_asset::Asset)

Register `fx_asset` as the conversion rate for assets priced in `ccy`. Its Close must be
**base-currency units per 1 unit of `ccy`**. The rate asset joins the market and every
current and future asset with `currency == ccy` converts through it.

```jldoctest
Random.seed!(1);
A=asset("AAPL");
A.currency=:EUR;
M=market([A]);
fx=asset("EURUSD");
set_fx!(M, :EUR, fx);
length(M.data)
# output

2
```
"""
function set_fx!(M::Market, ccy::Symbol, fx_asset::Asset)
  haskey(M.data, fx_asset.ticker) || add_asset!(M, fx_asset)
  M.fx_registry[ccy] = fx_asset.ticker
  return _rebuild_fx_wiring!(M)
end

"""
    timestamp(M::Market, i::Int)

Timestamp of bar `i`. Errors when the market has no axis.

```jldoctest
using Dates;
Random.seed!(1);
M=market([asset("AAPL")]);
set_axis!(M, DateTime(2000,1,1) .+ Day.(0:3650));
timestamp(M, 1)
# output

2000-01-01T00:00:00
```
"""
function timestamp(M::Market, i::Int)
  M.axis === nothing && error("Market has no time axis; see set_axis!")
  return M.axis[i]
end

"""
    bar_of(M::Market, t::DateTime)

Index of the last bar at or before `t` (0 if `t` precedes the axis). Errors when the
market has no axis.

```jldoctest
using Dates;
Random.seed!(1);
M=market([asset("AAPL")]);
set_axis!(M, DateTime(2000,1,1) .+ Day.(0:3650));
bar_of(M, DateTime(2000,1,10))
# output

10
```
"""
function bar_of(M::Market, t::DateTime)
  M.axis === nothing && error("Market has no time axis; see set_axis!")
  return searchsortedlast(M.axis, t)
end
bar_of(M::Market, t::Date) = bar_of(M, DateTime(t))

"""
    asset_names(M::Market)

Sorted ticker names — stable ordering for cross-sectional matrix rows.

```jldoctest
Random.seed!(1);
M=market([asset("BBB"), asset("AAA")]);
asset_names(M)
# output

2-element Vector{String}:
 "AAA"
 "BBB"
```
"""
asset_names(M::Market) = sort(collect(keys(M.data)))

"""
    returns_matrix(M::Market, window::UnitRange{Int}; key::String="Close")

`[N × (T-1)]` log-return matrix. Rows = assets (alpha order), cols = bars.
NaN/zero prices fill the corresponding column with 0.0.

```jldoctest
Random.seed!(1);
M=market([asset("AAPL")]);
size(returns_matrix(M, 1:5))
# output

(1, 4)
```
"""
function returns_matrix(M::Market, window::UnitRange{Int}; key::String="Close")
  nms = asset_names(M)
  N = length(nms)
  T = length(window)
  T < 2 && return Matrix{Float64}(undef, N, 0)

  R = zeros(Float64, N, T - 1)
  for (i, nm) in enumerate(nms)
    a = M.data[nm]
    row = a._idx[key]
    prices = a.data
    n_prices = size(prices, 2)
    for t in 1:(T - 1)
      t1, t2 = window[t], window[t + 1]
      p1 = t1 <= n_prices ? prices[row, t1] : NaN
      p2 = t2 <= n_prices ? prices[row, t2] : NaN
      if isfinite(p1) && isfinite(p2) && p1 > 0 && p2 > 0
        R[i, t] = log(p2 / p1)
      end
    end
  end
  return R
end

returns_matrix(M::Market; key::String="Close") = returns_matrix(M, 1:length(M); key=key)

"""
    trim_to_length(M::Market, n::Int)

New Market where every asset is trimmed to its last `n` bars.

```jldoctest
Random.seed!(1);
M=market([asset("AAPL")]);
length(trim_to_length(M, 10))
# output

10
```
"""
function trim_to_length(M::Market, n::Int)
  M2 = market(Asset[])
  for (_, a) in M.data
    len = length(a)
    start = max(1, len - n + 1)
    add_asset!(M2, a[start:len])
  end
  if M.axis !== nothing
    len = length(M.axis)
    M2.axis = M.axis[max(1, len - n + 1):len]
  end
  M2.fx_registry = copy(M.fx_registry)
  return _rewire_fx!(M2)
end
