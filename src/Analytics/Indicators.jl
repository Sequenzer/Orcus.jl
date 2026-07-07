
"""
    ema(v::Vector{Float64}, w::Int)

Exponential moving average with span `w` (α = 2/(w+1)).
Initialised with the SMA of the first `w` bars; `NaN` for earlier entries. Compatible with
`IndicatorGenerator`: `apply_indicator(IndicatorGenerator(ema, 20), asset, "Close", "EMA20")`.

```jldoctest
round.(ema([1.0,2.0,3.0,4.0,5.0,6.0,7.0], 3); digits=4)
# output

7-element Vector{Float64}:
 NaN
 NaN
   2.0
   3.0
   4.0
   5.0
   6.0
```
"""
function ema(v::Vector{Float64}, w::Int)::Vector{Float64}
  out = fill(NaN, length(v))
  length(v) < w && return out
  α = 2.0 / (w + 1)
  seed = mean(x for x in @view(v[1:w]) if !isnan(x))
  isnan(seed) && return out
  out[w] = seed
  for i in (w + 1):length(v)
    isnan(v[i]) ? (out[i] = out[i - 1]) : (out[i] = α * v[i] + (1.0 - α) * out[i - 1])
  end
  return out
end

"""
    ema(data::DataPoint)

Single-window EMA over `data`, weighting each successive entry by the EMA formula — the
`IndicatorGenerator`-compatible form (uses the window stored in `IndicatorGenerator`).

```jldoctest
round(ema([1.0,2.0,3.0]); digits=4)
# output

2.25
```
"""
ema(data::DataPoint)::Float64 = begin
  length(data) < 2 && return NaN
  # Simple approximation: return last value weighted by EMA formula over the whole window
  w = length(data)
  α = 2.0 / (w + 1)
  val = data[1]
  for i in 2:w
    val = α * data[i] + (1.0 - α) * val
  end
  return val
end

"""
    rsi(v::Vector{Float64}, w::Int=14)

Relative Strength Index using Wilder's smoothing.
Returns values in [0, 100]; `NaN` for the first `w` bars. Compatible with
`IndicatorGenerator`: `apply_indicator(IndicatorGenerator(rsi, 14), asset, "Close", "RSI14")`.

```jldoctest
v=[1.0,2.0,1.5,2.5,3.0,2.0,3.5,4.0,3.0,5.0,4.5,6.0,5.5,7.0,6.5,8.0];
round.(rsi(v, 5); digits=4)
# output

16-element Vector{Float64}:
 NaN
 NaN
 NaN
 NaN
 NaN
  62.5
  74.4681
  77.4648
  59.8911
  74.4065
  66.8466
  75.9934
  68.1582
  77.0367
  69.0182
  77.7161
```
"""
function rsi(v::Vector{Float64}, w::Int=14)::Vector{Float64}
  out = fill(NaN, length(v))
  length(v) < w + 1 && return out
  diffs = diff(v)
  gains = max.(diffs, 0.0)
  losses = max.(-diffs, 0.0)
  avg_g = mean(@view gains[1:w])
  avg_l = mean(@view losses[1:w])
  rs = avg_l < 1e-10 ? Inf : avg_g / avg_l
  out[w + 1] = 100.0 - 100.0 / (1.0 + rs)
  for i in (w + 1):length(diffs)
    avg_g = (avg_g * (w - 1) + gains[i]) / w
    avg_l = (avg_l * (w - 1) + losses[i]) / w
    rs = avg_l < 1e-10 ? Inf : avg_g / avg_l
    out[i + 1] = 100.0 - 100.0 / (1.0 + rs)
  end
  return out
end

"""
    atr(high::Vector{Float64}, low::Vector{Float64}, close::Vector{Float64}, w::Int=14)

Average True Range using Wilder's smoothing: True Range = max(H-L, |H-prev_C|, |L-prev_C|).
Returns `NaN` for the first `w+1` bars. Not directly `IndicatorGenerator`-compatible (needs
three input series) — call directly in strategy logic.

```jldoctest
h=[10.0,11.0,10.5,12.0,11.5,13.0,12.5];
l=[9.0,10.0,9.5,11.0,10.5,12.0,11.5];
c=[9.5,10.5,10.0,11.5,11.0,12.5,12.0];
round.(atr(h,l,c,3); digits=4)
# output

7-element Vector{Float64}:
 NaN
 NaN
 NaN
   1.5
   1.3333
   1.5556
   1.3704
```
"""
function atr(high::Vector{Float64}, low::Vector{Float64},
  close::Vector{Float64}, w::Int=14)::Vector{Float64}
  n = length(high)
  out = fill(NaN, n)
  n < w + 1 && return out
  tr = Vector{Float64}(undef, n - 1)
  for i in 2:n
    tr[i - 1] = max(high[i] - low[i],
      abs(high[i] - close[i - 1]),
      abs(low[i] - close[i - 1]))
  end
  out[w + 1] = mean(@view tr[1:w])
  for i in (w + 1):length(tr)
    out[i + 1] = (out[i] * (w - 1) + tr[i]) / w
  end
  return out
end
