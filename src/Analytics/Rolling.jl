
export rolling_mean, rolling_std, rolling_zscore

"""
    rolling_mean(v, w) -> Vector{Float64}

Rolling mean of `v` with window `w`. First `w-1` entries are `NaN`.
"""
function rolling_mean(v::Vector{Float64}, w::Int)::Vector{Float64}
    out = fill(NaN, length(v))
    for i in w:length(v)
        out[i] = mean(@view v[i-w+1:i])
    end
    return out
end

"""
    rolling_std(v, w) -> Vector{Float64}

Rolling standard deviation of `v` with window `w`. First `w-1` entries are `NaN`.
"""
function rolling_std(v::Vector{Float64}, w::Int)::Vector{Float64}
    out = fill(NaN, length(v))
    for i in w:length(v)
        out[i] = std(@view v[i-w+1:i])
    end
    return out
end

"""
    rolling_zscore(v, w) -> Vector{Float64}

Rolling z-score of `v` with window `w`: `(v[i] - mean(v[i-w+1:i])) / std(...)`.
First `w-1` entries are `NaN`. Bars with zero local standard deviation are `NaN`.

Can also be used as an `IndicatorGenerator` function:
```julia
apply_indicator(IndicatorGenerator(rolling_zscore, 30), asset, "Close", "ZScore30")
```
"""
function rolling_zscore(v::Vector{Float64}, w::Int)::Vector{Float64}
    mu  = rolling_mean(v, w)
    sig = rolling_std(v, w)
    out = fill(NaN, length(v))
    for i in w:length(v)
        sig[i] < 1e-10 && continue
        out[i] = (v[i] - mu[i]) / sig[i]
    end
    return out
end

# IndicatorGenerator-compatible single-window form (DataPoint → Float64)
rolling_zscore(data::DataPoint)::Float64 = begin
    length(data) < 2 && return NaN
    mu, sigma = mean(data), std(data)
    sigma < 1e-10 && return NaN
    return (last(data) - mu) / sigma
end
