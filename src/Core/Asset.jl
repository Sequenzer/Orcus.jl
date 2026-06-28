
import Base: getindex, setindex!, length, show, size, names


export Asset,
    asset,
    height,
    data,
    n_datasets,
    randOHLC,
    calculate_indicator,
    apply_indicator,
    value,
    add_datapoint!,
    rowindex,
    shorten!


"""
    Asset

A single instrument's price/indicator data.

`data` is an `AbstractMatrix{Float64}` with shape `[n_datasets × n_bars]`.
During a backtest the broker's assets hold a SubArray view into the base market
data — zero-copy bar advancement. Outside the loop (and after `copy`) it is
always a concrete `Matrix{Float64}`.

NaN is used as the sentinel for missing/gap bars — no Union boxing.
"""
mutable struct Asset
    ticker::String
    data::Matrix{Float64}             # concrete (no views) — type-stable indexing
    data_id::Vector{String}
    _idx::Dict{String,Int}            # row-name → row index, O(1) lookup
    indicator_functions::Vector{Union{Nothing,Tuple{IndicatorGenerator,String}}}
    visible::Int                      # bars currently revealed (cursor); 1:visible is "now"
    close_idx::Int                    # cached row index of "Close" (0 if absent) — hot path avoids the String hash

    function Asset(ticker::String,
                   data::AbstractMatrix{Float64}=DataSeries(undef, 4, 0),
                   data_id::Vector{String}=fill("", size(data, 1)))

        @assert size(data, 1) == length(data_id)
        this = new()
        this.ticker   = ticker
        this.data     = convert(Matrix{Float64}, data)
        this.data_id  = data_id
        this._idx     = Dict(id => i for (i, id) in enumerate(data_id))
        this.indicator_functions = fill(nothing, length(data_id))
        this.visible  = size(this.data, 2)
        this.close_idx = get(this._idx, "Close", 0)
        return this
    end
end

asset(ticker::String, data::AbstractMatrix{Float64}, data_id::Vector{String}) =
    Asset(ticker, data, data_id)

function asset()
    ticker = randstring('A':'Z', 4)
    ohlc, data_id = randOHLC(100, x->rand()-0.5, 1:5:3653, 10)
    return Asset(ticker, ohlc, data_id)
end

function asset(ticker::String)
    ohlc, data_id = randOHLC(100, x->rand()-0.5, 1:5:3653, 10)
    return Asset(ticker, ohlc, data_id)
end

function asset(ticker::String, interval::StepRange{Int,Int}, prop_func::Function,
               base::Real=100, precision::Int=10)
    ohlc, data_id = randOHLC(base, prop_func, interval, precision)
    return Asset(ticker, ohlc, data_id)
end


data(A::Asset) = A.data

"""
    rowindex(A::Asset, name::String) -> Int

Row index of the named series (`0` if absent). Resolve once (e.g. in a strategy's `init`) and
read with the integer accessor `A[row, col]` to skip the per-call `String` hash on the hot path.
"""
rowindex(A::Asset, name::String) = get(A._idx, name, 0)

Base.show(io::IO, A::Asset) = print(io, "Asset '$(A.ticker)' with $(n_datasets(A)) datasets")

# Indexing by row index
Base.getindex(A::Asset, key1::Int, key2::Int)     = A.data[key1, key2]
Base.getindex(A::Asset, key1::Int, ::Colon)        = A.data[key1, 1:A.visible]
Base.getindex(A::Asset, ::Colon,  key2::Int)       = A.data[:, key2]
Base.getindex(A::Asset, ::Colon,  ::Colon)         = A.data

# Indexing by name — O(1) via _idx; bounded to the visible window (no lookahead)
function Base.getindex(A::Asset, key::String)
    row = get(A._idx, key, 0)
    row == 0 && return missing
    A.data[row, 1:A.visible]
end

function Base.getindex(A::Asset, key::String, ::Colon)
    getindex(A, key)
end

function Base.getindex(A::Asset, key::String, key2::Int)
    row = get(A._idx, key, 0)
    row == 0 && return missing
    A.data[row, key2]
end

function Base.copy(A::Asset)
    B = Asset(A.ticker, Matrix{Float64}(A.data), copy(A.data_id))
    B.indicator_functions = copy(A.indicator_functions)
    B.visible = A.visible
    return B
end

function Base.getindex(A::Asset, r::UnitRange{Int})
    B = copy(A)
    B.data = Matrix{Float64}(A.data[:, r])
    B.visible = size(B.data, 2)
    return B
end

Base.names(A::Asset) = A.data_id

function Base.setindex!(A::Asset, dp::DataPoint, key1::String)
    index = get(A._idx, key1, nothing)
    if isnothing(index)
        @assert length(dp) == size(A.data, 2)
        # Materialize view before growing (adding a row is only valid in init)
        mat = Matrix{Float64}(A.data)
        push!(A.data_id, key1)
        new_row = length(A.data_id)
        A._idx[key1] = new_row
        A.data = vcat(mat, transpose(dp))
        push!(A.indicator_functions, nothing)
    else
        A.data[index, :] .= dp
    end
    return A
end

function Base.setindex!(A::Asset, dp::DataPoint, key1::Int, ::Colon)
    @assert length(dp) == size(A.data, 2)
    @assert key1 <= size(A.data, 1)
    A.data[key1, :] .= dp
    return A
end

Base.length(A::Asset)  = A.visible          # bars currently revealed (cursor)
height(A::Asset)       = size(A.data, 1)
n_datasets(A::Asset)   = height(A)
Base.size(A::Asset)    = (height(A), A.visible)

"""
    randOHLC(base, f, interval, precision) -> (DataSeries, Vector{String})

Generate synthetic OHLC bars. Non-sampled bars are filled with NaN.
"""
function randOHLC(base::Number, f::Function, interval::StepRange{Int,Int}, precision::Int)
    full_interval = interval.start:1:interval.stop
    data_id = ["Open", "High", "Low", "Close"]
    ohlc = fill(NaN, length(data_id), length(full_interval))

    lst = base
    for i in full_interval
        rem(i - 1, step(interval)) !== 0 && continue
        arr       = randomValue(lst, precision, f)
        sortedarr = sort(arr)
        ohlc[1, i] = first(arr)
        ohlc[2, i] = last(sortedarr)
        ohlc[3, i] = first(sortedarr)
        ohlc[4, i] = last(arr)
        lst = last(arr)
    end
    return ohlc, data_id
end

"""
    calculate_indicator(Ind, asset, data_key)

Compute an indicator series over the asset's named column.
NaN bars in the source propagate as NaN in the output.
"""
function calculate_indicator(Ind::IndicatorGenerator, asset::Asset, data_key::String)
    @assert haskey(asset._idx, data_key)
    src       = asset[data_key]
    indicator = fill(NaN, length(src))
    for i in eachindex(src)
        i <= Ind.window && continue
        window_vals = src[i-Ind.window+1:i]
        all(isnan, window_vals) && continue   # only skip wholly-empty windows; NaN handling is the calc_func's job
        indicator[i] = Ind.calc_func(window_vals)
    end
    return indicator
end

"""
    apply_indicator(Ind, asset, data_key, name)

Compute and attach a named indicator row to the asset.
Must be called in `init`, not `next` (asset.data may be a view during backtest).
"""
function apply_indicator(Ind::IndicatorGenerator, asset::Asset,
                         data_key::String, name::String)
    asset[name] = calculate_indicator(Ind, asset, data_key)
    i = asset._idx[name]
    if i > length(asset.indicator_functions)
        push!(asset.indicator_functions, (Ind, data_key))
    else
        asset.indicator_functions[i] = (Ind, data_key)
    end
    return asset
end

"""
    value(A::Asset, data_key="Close")

Current price: last non-NaN value in the named row.
O(1) for clean CSV data (no NaN at end), O(n_gaps) for sparse synthetic data.
"""
@inline value(A::Asset) = _value_at(A, A.close_idx > 0 ? A.close_idx : A._idx["Close"])
@inline value(A::Asset, data_key::String) = _value_at(A, A._idx[data_key])

# Last non-NaN value in `row`, scanning back from the visible cursor (no lookahead).
# The `col == 0` guard also covers the empty/all-NaN asset (no separate length assert needed).
@inline function _value_at(A::Asset, row::Int)
    col = A.visible
    @inbounds while col > 0 && isnan(A.data[row, col])
        col -= 1
    end
    col == 0 && error("No valid data in $(A.ticker)")
    @inbounds A.data[row, col]
end

function get_data(A::Asset, i::Int)
    A.data[i, :]
end

"""
    shorten!(A::Asset, u::UnitRange{Int})

Trim asset data to the given column range (materializes views).
"""
function shorten!(A::Asset, u::UnitRange{Int})
    A.data = Matrix{Float64}(A.data[:, u])
    A.visible = size(A.data, 2)
    return A
end

"""
    add_datapoint!(A::Asset, dp::DataPoint)

Append a new bar (column) to the asset, recomputing indicator rows.
"""
function add_datapoint!(A::Asset, dp::DataPoint)
    @assert length(dp) == height(A)
    for i in eachindex(A.data_id)
        @assert isnothing(A.indicator_functions[i]) || isnan(dp[i])
    end
    for i in eachindex(A.indicator_functions)
        if !isnothing(A.indicator_functions[i])
            Ind, name = A.indicator_functions[i]
            j = A._idx[name]
            window_vals = A.data[j, end-Ind.window+1:end]
            dp[i] = any(isnan, window_vals) ? NaN : Ind.calc_func(window_vals)
        end
    end
    A.data = hcat(A.data, dp)
    A.visible = size(A.data, 2)
    return A
end
