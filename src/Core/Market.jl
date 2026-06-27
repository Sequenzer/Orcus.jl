

export Market,
       market,
       addAsset!,
       addAssets!,
       assets,
       start_date,
       to_asset,
       end_date,
       to_market,
       names,
       set_data_to!,
       advance_to!,
       asset_names,
       returns_matrix,
       trim_to_length

"""
    Market

A collection of Assets keyed by ticker. `_length` caches the maximum bar count
so `length(M)` is O(1) instead of scanning all assets every call.
"""
mutable struct Market
    data::Dict{String,Asset}
    assets::Vector{Asset}        # same Assets as `data`, contiguous for hash-free hot-path iteration
    _length::Int

    function Market(assets::Vector{Asset})
        this = new()
        this.data    = Dict{String,Asset}()
        this.assets  = Asset[]
        this._length = 0
        for a in assets
            addAsset!(this, a)
        end
        return this
    end
    Market(asset::Asset) = Market([asset])
    Market() = new(Dict{String,Asset}(), Asset[], 0)
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
Base.getindex(M::Market, i::Int)         = values(M.data)[i]

assets(M::Market) = values(M.data)

Base.length(M::Market) = M._length       # O(1) — cached
height(M::Market)      = length(M.data)
Base.size(M::Market)   = (height(M), length(M))
Base.names(M::Market)  = keys(M.data)

function addAsset!(M::Market, A::Asset)
    if haskey(M.data, A.ticker)                     # replacing: keep the vector in sync, no dup
        old = M.data[A.ticker]
        idx = findfirst(===(old), M.assets)
        idx === nothing ? push!(M.assets, A) : (M.assets[idx] = A)
    else
        push!(M.assets, A)
    end
    M.data[A.ticker] = A
    M._length = max(M._length, length(A))
    return M
end

function addAssets!(M::Market, assets::AbstractVector{Asset})
    for a in assets
        addAsset!(M, a)
    end
end

Base.getindex(M::Market, key2::Int, ::Colon)          = to_asset(M)[key2, :]
Base.getindex(M::Market, key1::Int, key2::Int)         = to_asset(M)[key1, key2]
Base.getindex(M::Market, ::Colon,   key2::Int)         = to_asset(M)[:, key2]
Base.copy(M::Market) = Market([copy(A) for A in values(M.data)])

function Base.getindex(M::Market, r::UnitRange{Int})
    newM = Market(Asset[])
    for (_, v) in M.data
        addAsset!(newM, v[r])
    end
    return newM
end

function shorten!(M::Market, U::UnitRange{Int})
    for (_, v) in M.data
        shorten!(v, U)
    end
    M._length = length(U)
end

function cutDataUntil(M::Market, n::Int)
    newMarket = Market()
    for (k, v) in M.data
        newMarket.data[k] = cutDataUntil(v, n)
    end
    return newMarket
end

function takeData!(source::Market, target::Market, date::DateTime)
    for (k, v) in target.data
        haskey(source.data, k) && takeData!(source.data[k], v, date)
    end
end
function takeData!(source::Market, target::Market, n::Int)
    for (k, v) in target.data
        haskey(source.data, k) && takeData!(source.data[k], v, n)
    end
end

function getDomain(M::Market)
    domain = Vector{DateTime}()
    for (_, v) in M.data
        append!(domain, getDomain(v))
    end
    return sort(unique(domain))
end

function to_asset(M::Market)
    @assert length(unique(names(M))) == length(names(M))
    ats       = assets(M)
    len       = maximum(length.(ats))
    dt        = DataSeries(undef, 0, len)
    namesToAdd = String[]
    for (k, v) in M.data
        dt = vcat(dt, Matrix{Float64}(v.data))
        append!(namesToAdd, k * "_" .* names(v))
    end
    return asset("Market", dt, namesToAdd)
end

function to_market(A::Asset)
    M   = market()
    nms = split.(names(A), "_")
    return nms
end

"""
    advance_to!(M, i)

Reveal bars `1:i` of every asset by moving its `visible` cursor — O(N_assets) integer
writes, **zero allocation**. Each asset already holds its full price matrix; advancing the
cursor is what the backtest loop does once per bar (replaces the old SubArray view churn).
"""
function advance_to!(M::Market, i::Int)
    max_len = 0
    @inbounds for a in M.assets        # contiguous Vector — no Dict hashing per bar
        a.visible = min(i, size(a.data, 2))
        max_len   = max(max_len, a.visible)
    end
    M._length = max_len
    return M
end

"""
    set_data_to!(M, N, u)

Back-compat shim for the old view-based API: advances `M` to reveal bars `1:last(u)` via the
`visible` cursor (`M` already holds the full series). `N` is ignored. Prefer [`advance_to!`](@ref).
"""
set_data_to!(M::Market, N::Market, u::UnitRange{Int}) = advance_to!(M, last(u))

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
    N   = length(nms)
    T   = length(window)
    T < 2 && return Matrix{Float64}(undef, N, 0)

    R = zeros(Float64, N, T - 1)
    for (i, nm) in enumerate(nms)
        a        = M.data[nm]
        row      = a._idx[key]
        prices   = a.data
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
        len   = length(a)
        start = max(1, len - n + 1)
        addAsset!(M2, a[start:len])
    end
    return M2
end
