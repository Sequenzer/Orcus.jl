
export bsm_call, bsm_put, bsm_delta, realized_vol

# Standard normal CDF — Abramowitz & Stegun 26.2.17, max error 7.5e-8
function _normcdf(x::Float64)::Float64
  t = 1.0 / (1.0 + 0.2316419 * abs(x))
  poly =
    t * (
      0.319381530 +
      t * (-0.356563782 +
           t * (1.781477937 + t * (-1.821255978 + t * 1.330274429)))
    )
  prob = 1.0 - (1.0 / sqrt(2π)) * exp(-0.5 * x^2) * poly
  return x >= 0 ? prob : 1.0 - prob
end

"""
    bsm_call(S, K, T, r, sigma) -> Float64

Black-Scholes-Merton European call price.
- `S`     current underlying price
- `K`     strike
- `T`     time to expiry in years (e.g., 21/252 for one month)
- `r`     risk-free rate (annualized, e.g., 0.04)
- `sigma` annualized volatility (e.g., 0.20)

Returns intrinsic value `max(S-K, 0)` when `T ≤ 0`.
"""
function bsm_call(S::Float64, K::Float64, T::Float64,
  r::Float64, sigma::Float64)::Float64
  (T <= 0 || sigma <= 0) && return max(S - K, 0.0)
  d1 = (log(S / K) + (r + 0.5 * sigma^2) * T) / (sigma * sqrt(T))
  d2 = d1 - sigma * sqrt(T)
  return S * _normcdf(d1) - K * exp(-r * T) * _normcdf(d2)
end

"""
    bsm_put(S, K, T, r, sigma) -> Float64

Black-Scholes-Merton European put price (via put-call parity).
"""
function bsm_put(S::Float64, K::Float64, T::Float64,
  r::Float64, sigma::Float64)::Float64
  (T <= 0 || sigma <= 0) && return max(K - S, 0.0)
  d1 = (log(S / K) + (r + 0.5 * sigma^2) * T) / (sigma * sqrt(T))
  d2 = d1 - sigma * sqrt(T)
  return K * exp(-r * T) * _normcdf(-d2) - S * _normcdf(-d1)
end

"""
    bsm_delta(S, K, T, r, sigma; type=:call) -> Float64

Black-Scholes-Merton option delta.
`type` is `:call` (default) or `:put`.
Call delta ∈ (0, 1); put delta ∈ (-1, 0).
"""
function bsm_delta(S::Float64, K::Float64, T::Float64,
  r::Float64, sigma::Float64;
  type::Symbol=:call)::Float64
  if T <= 0 || sigma <= 0
    return type == :call ? Float64(S > K) : Float64(S < K) - 1.0
  end
  d1 = (log(S / K) + (r + 0.5 * sigma^2) * T) / (sigma * sqrt(T))
  return type == :call ? _normcdf(d1) : _normcdf(d1) - 1.0
end

"""
    realized_vol(prices, window=20) -> Float64

Annualized realized volatility estimated from the last `window` log-returns
of a price series. Returns `NaN` if insufficient data.
"""
function realized_vol(prices::Vector{Float64}, window::Int=20)::Float64
  clean = filter(x -> !isnan(x) && x > 0, prices)
  length(clean) < window + 1 && return NaN
  rets = diff(log.(clean[(end - window):end]))
  σ = std(rets)
  isnan(σ) && return NaN
  return σ * sqrt(252)
end
