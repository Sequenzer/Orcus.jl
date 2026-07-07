
_resample_stops(n::Int, k::Int) = n == 0 ? Int[] : collect(k:k:n) ∪ [n]

function _period_stops(axis::Vector{DateTime}, p::Dates.Period)
  stops = Int[]
  for j in 1:(length(axis) - 1)
    Dates.floor(axis[j], p) != Dates.floor(axis[j + 1], p) && push!(stops, j)
  end
  push!(stops, length(axis))
  return stops
end

function _first_valid(row::AbstractVector{Float64}, lo::Int, hi::Int)
  for j in lo:hi
    isnan(row[j]) || return row[j]
  end
  return NaN
end

function _last_valid(row::AbstractVector{Float64}, lo::Int, hi::Int)
  for j in hi:-1:lo
    isnan(row[j]) || return row[j]
  end
  return NaN
end

function _agg(rule::Symbol, row::AbstractVector{Float64}, lo::Int, hi::Int)
  rule === :first && return _first_valid(row, lo, hi)
  rule === :last && return _last_valid(row, lo, hi)
  acc = NaN
  for j in lo:hi
    v = row[j]
    isnan(v) && continue
    if isnan(acc)
      acc = v
    elseif rule === :max
      acc = max(acc, v)
    elseif rule === :min
      acc = min(acc, v)
    else
      acc += v                       # :sum
    end
  end
  return acc
end

function _row_rule(name::String)
  name == "Open" && return :first
  name == "High" && return :max
  name == "Low" && return :min
  name == "Volume" && return :sum
  return :last                       # Close, indicators, anything else
end

function _resample(M::Market, stops::Vector{Int})
  isempty(M.assets) && error("cannot resample an empty market")
  width = size(M.assets[1].data, 2)
  @assert all(a -> size(a.data, 2) == width, M.assets) "resample requires equal asset widths"
  isempty(stops) && error("no bars to resample")
  @assert last(stops) == width

  M2 = market()
  for A in M.assets
    out = Matrix{Float64}(undef, height(A), length(stops))
    for r in 1:height(A)
      rule = _row_rule(A.data_id[r])
      row = view(A.data, r, :)
      lo = 1
      for (g, hi) in enumerate(stops)
        out[r, g] = _agg(rule, row, lo, hi)
        lo = hi + 1
      end
    end
    add_asset!(M2, Asset(A.ticker, out, copy(A.data_id); currency=A.currency))
  end
  M.axis === nothing || (M2.axis = M.axis[stops])
  M2.fx_registry = copy(M.fx_registry)
  return _rewire_fx!(M2)
end

"""
    resample(M::Market, k::Int)
    resample(M::Market, p::Dates.Period)

New Market with bars aggregated `k`-to-1 (or grouped by calendar period, which requires a
time axis): Open = first, High = max, Low = min, Volume = sum, everything else (Close,
indicators) = last. Attached indicator generators are not carried over — re-apply indicators
on the resampled market.

```jldoctest
M=market([asset("AAPL")]);
length(resample(M, 5))
# output

731
```
"""
function resample(M::Market, k::Int)
  k >= 1 || error("resample factor must be >= 1")
  width = isempty(M.assets) ? 0 : size(M.assets[1].data, 2)
  return _resample(M, _resample_stops(width, k))
end

function resample(M::Market, p::Dates.Period)
  M.axis === nothing && error("resample by period requires a time axis; see set_axis!")
  return _resample(M, _period_stops(M.axis, p))
end
