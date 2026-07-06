
export Market,
  market,
  add_asset!,
  add_assets!,
  assets,
  to_asset,
  to_market,
  names,
  set_data_to!,
  advance_to!,
  asset_names,
  returns_matrix,
  trim_to_length,
  set_axis!,
  has_axis,
  timestamp,
  bar_of,
  set_fx!

"""
    Market

A collection of Assets keyed by ticker. `_length` caches the maximum bar count
so `length(M)` is O(1) instead of scanning all assets every call. `axis` is an
optional shared time axis: `axis[j]` labels bar `j` of every asset; `nothing`
means bars are abstract integer indices. The engine never reads it per bar.
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

market(assets::Vector{Asset}) = Market(assets)
market() = market(Asset[])
market(asset::Asset) = market([asset])
market(n_Assets::Int) = Market([asset() for i in 1:n_Assets])

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
height(M::Market) = length(M.data)
Base.size(M::Market) = (height(M), length(M))
Base.names(M::Market) = keys(M.data)

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

# Re-derive all fx wiring (asset `fx` refs, current rates, and the hot-path pair list) from
# the registry. Cold path — called on any wiring or membership change, never per bar.
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

# Repoint every asset's cached fx reference at THIS market's rate assets. Required after
# any operation that copies/rebuilds assets: a stale reference into the source market means
# another thread's `advance_to!` moves the rate under us (see the batch isolation model).
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
    advance_to!(M, i)

Reveal bars `1:i` of every asset by moving its `visible` cursor — O(N_assets) integer
writes, **zero allocation**. Each asset already holds its full price matrix; advancing the
cursor is what the backtest loop does once per bar (replaces the old SubArray view churn).
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
"""
set_data_to!(M::Market, N::Market, u::UnitRange{Int}) = advance_to!(M, last(u))

"""
    set_axis!(M::Market, axis::Vector{DateTime}) -> Market

Attach a shared time axis: `axis[j]` labels bar `j` of every asset. Must be sorted and
match the full data width of the market's widest asset.
"""
function set_axis!(M::Market, axis::Vector{DateTime})
  @assert issorted(axis) "axis must be sorted ascending"
  width = maximum(a -> size(a.data, 2), M.assets; init=0)
  @assert length(axis) == width "axis length $(length(axis)) != market data width $width"
  M.axis = axis
  return M
end
set_axis!(M::Market, axis::Vector{Date}) = set_axis!(M, DateTime.(axis))

has_axis(M::Market) = M.axis !== nothing

"""
    set_fx!(M::Market, ccy::Symbol, fx_asset::Asset) -> Market

Register `fx_asset` as the conversion rate for assets priced in `ccy`. Its Close must be
**base-currency units per 1 unit of `ccy`**. The rate asset joins the market (so its bar
cursor advances with everything else) and every current and future asset with
`currency == ccy` converts through it.
"""
function set_fx!(M::Market, ccy::Symbol, fx_asset::Asset)
  haskey(M.data, fx_asset.ticker) || add_asset!(M, fx_asset)
  M.fx_registry[ccy] = fx_asset.ticker
  return _rebuild_fx_wiring!(M)
end

"""
    timestamp(M::Market, i::Int) -> DateTime

Timestamp of bar `i`. Errors when the market has no axis.
"""
function timestamp(M::Market, i::Int)
  M.axis === nothing && error("Market has no time axis; see set_axis!")
  return M.axis[i]
end

"""
    bar_of(M::Market, t) -> Int

Index of the last bar at or before `t` (0 if `t` precedes the axis). Errors when the
market has no axis.
"""
function bar_of(M::Market, t::DateTime)
  M.axis === nothing && error("Market has no time axis; see set_axis!")
  return searchsortedlast(M.axis, t)
end
bar_of(M::Market, t::Date) = bar_of(M, DateTime(t))

"""
    asset_names(M::Market) -> Vector{String}

Sorted ticker names — stable ordering for cross-sectional matrix rows.
"""
asset_names(M::Market) = sort(collect(keys(M.data)))

"""
    returns_matrix(M, window; key="Close") -> Matrix{Float64}

`[N × (T-1)]` log-return matrix. Rows = assets (alpha order), cols = bars.
NaN/zero prices fill the corresponding column with 0.0.
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

returns_matrix(M::Market; key::String="Close") =
  returns_matrix(M, 1:length(M); key=key)

"""
    trim_to_length(M, n) -> Market

New Market where every asset is trimmed to its last `n` bars.
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
