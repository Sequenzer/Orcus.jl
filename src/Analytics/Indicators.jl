
export ema, rsi, atr

"""
    ema(v, w) -> Vector{Float64}

Exponential moving average with span `w` (α = 2/(w+1)).
Initialised with the SMA of the first `w` bars; `NaN` for earlier entries.
Compatible with `IndicatorGenerator`:
```julia
apply_indicator(IndicatorGenerator(ema, 20), asset, "Close", "EMA20")
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

# IndicatorGenerator-compatible DataPoint form (uses the window stored in IndicatorGenerator)
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
    rsi(v, w=14) -> Vector{Float64}

Relative Strength Index using Wilder's smoothing.
Returns values in [0, 100]; `NaN` for the first `w` bars.
Compatible with `IndicatorGenerator`:
```julia
apply_indicator(IndicatorGenerator(rsi, 14), asset, "Close", "RSI14")
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
    atr(high, low, close, w=14) -> Vector{Float64}

Average True Range using Wilder's smoothing.
True Range = max(H-L, |H-prev_C|, |L-prev_C|).
Returns `NaN` for the first `w+1` bars.
Not directly IndicatorGenerator-compatible (needs three input series);
call directly in strategy logic:
```julia
h = Float64.(asset["High"]); l = Float64.(asset["Low"]); c = Float64.(asset["Close"])
atr_val = last(filter(!isnan, atr(h, l, c, 14)))
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
