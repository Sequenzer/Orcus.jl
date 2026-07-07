
"""
    rolling_mean(v::Vector{Float64}, w::Int)

Rolling mean of `v` with window `w`. First `w-1` entries are `NaN`.

```jldoctest
rolling_mean([1.0,2.0,3.0,4.0,5.0], 3)
# output

5-element Vector{Float64}:
 NaN
 NaN
   2.0
   3.0
   4.0
```
"""
function rolling_mean(v::Vector{Float64}, w::Int)::Vector{Float64}
  out = fill(NaN, length(v))
  for i in w:length(v)
    out[i] = mean(@view v[(i - w + 1):i])
  end
  return out
end

"""
    rolling_std(v::Vector{Float64}, w::Int)

Rolling standard deviation of `v` with window `w`. First `w-1` entries are `NaN`.

```jldoctest
rolling_std([1.0,2.0,3.0,4.0,5.0], 3)
# output

5-element Vector{Float64}:
 NaN
 NaN
   1.0
   1.0
   1.0
```
"""
function rolling_std(v::Vector{Float64}, w::Int)::Vector{Float64}
  out = fill(NaN, length(v))
  for i in w:length(v)
    out[i] = std(@view v[(i - w + 1):i])
  end
  return out
end

"""
    rolling_zscore(v::Vector{Float64}, w::Int)

Rolling z-score of `v` with window `w`: `(v[i] - mean(v[i-w+1:i])) / std(...)`.
First `w-1` entries are `NaN`. Bars with zero local standard deviation are `NaN`.

```jldoctest
rolling_zscore([1.0,2.0,3.0,4.0,5.0], 3)
# output

5-element Vector{Float64}:
 NaN
 NaN
   1.0
   1.0
   1.0
```
"""
function rolling_zscore(v::Vector{Float64}, w::Int)::Vector{Float64}
  mu = rolling_mean(v, w)
  sig = rolling_std(v, w)
  out = fill(NaN, length(v))
  for i in w:length(v)
    sig[i] < 1e-10 && continue
    out[i] = (v[i] - mu[i]) / sig[i]
  end
  return out
end

"""
    rolling_zscore(data::DataPoint)

Single-window z-score of the last entry in `data` against the whole vector's mean/std — the
`IndicatorGenerator`-compatible form: `apply_indicator(IndicatorGenerator(rolling_zscore, 30),
asset, "Close", "ZScore30")`.

```jldoctest
rolling_zscore([1.0,2.0,3.0])
# output

1.0
```
"""
rolling_zscore(data::DataPoint)::Float64 = begin
  length(data) < 2 && return NaN
  mu, sigma = mean(data), std(data)
  sigma < 1e-10 && return NaN
  return (last(data) - mu) / sigma
end
