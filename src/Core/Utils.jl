export random_value,
  DataSeries,
  DataPoint,
  data_series,
  data_point,
  add!

IncompleteVector = AbstractVector{<:Union{<:Real,Missing}}

function random_value(x::Real, n::Int, f::Function)
  arr::Vector{Real} = [x]
  while (length(arr) < n)
    old = last(arr)
    push!(arr, old + f(old))
  end
  return arr
end

# NaN is the sentinel for missing/gap data. All price/indicator arrays are
# plain Float64 — no boxing, SIMD-friendly, compatible with isnan() guards.
DataPoint = Vector{Float64}
DataSeries = Matrix{Float64}

function data_series(x::Vector{DataPoint})
  isempty(x) && return DataSeries(undef, 0, 0)
  hght = length(x)
  lgth = maximum(length.(x))
  arr = fill(NaN, hght, lgth)
  for i in eachindex(x)
    n = length(x[i])
    for j in 1:n
      arr[i, j] = x[i][j]
    end
  end
  return arr
end

data_point(x::Vector{<:Real}) = DataPoint(x)
data_point(n::Int) = fill(NaN, n)

function add!(x::DataSeries, y::DataPoint; start=1)
  n = size(x, 2)
  new_n = max(n, length(y) + start - 1)
  new_x = fill(NaN, size(x, 1), new_n)
  new_x[:, 1:n] .= x
  for j in eachindex(y)
    new_x[end, start + j - 1] = y[j]
  end
  return new_x
end
