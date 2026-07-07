
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
    bsm_call(S::Float64, K::Float64, T::Float64, r::Float64, sigma::Float64)

Black-Scholes-Merton European call price for underlying price `S`, strike `K`, time to
expiry `T` in years, annualized risk-free rate `r`, and annualized volatility `sigma`.
Returns intrinsic value `max(S-K, 0)` when `T ≤ 0`.

```jldoctest
round(bsm_call(100.0, 100.0, 0.25, 0.04, 0.2); digits=4)
# output

4.4852
```
"""
function bsm_call(S::Float64, K::Float64, T::Float64,
  r::Float64, sigma::Float64)::Float64
  (T <= 0 || sigma <= 0) && return max(S - K, 0.0)
  d1 = (log(S / K) + (r + 0.5 * sigma^2) * T) / (sigma * sqrt(T))
  d2 = d1 - sigma * sqrt(T)
  return S * _normcdf(d1) - K * exp(-r * T) * _normcdf(d2)
end

"""
    bsm_put(S::Float64, K::Float64, T::Float64, r::Float64, sigma::Float64)

Black-Scholes-Merton European put price (via put-call parity).

```jldoctest
round(bsm_put(100.0, 100.0, 0.25, 0.04, 0.2); digits=4)
# output

3.4902
```
"""
function bsm_put(S::Float64, K::Float64, T::Float64,
  r::Float64, sigma::Float64)::Float64
  (T <= 0 || sigma <= 0) && return max(K - S, 0.0)
  d1 = (log(S / K) + (r + 0.5 * sigma^2) * T) / (sigma * sqrt(T))
  d2 = d1 - sigma * sqrt(T)
  return K * exp(-r * T) * _normcdf(-d2) - S * _normcdf(-d1)
end

"""
    bsm_delta(S::Float64, K::Float64, T::Float64, r::Float64, sigma::Float64; type::Symbol=:call)

Black-Scholes-Merton option delta. `type` is `:call` (default) or `:put`.
Call delta ∈ (0, 1); put delta ∈ (-1, 0).

```jldoctest
round(bsm_delta(100.0, 100.0, 0.25, 0.04, 0.2); digits=4)
# output

0.5596
```
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
    realized_vol(prices::Vector{Float64}, window::Int=20)

Annualized realized volatility estimated from the last `window` log-returns
of a price series. Returns `NaN` if insufficient data.

```jldoctest
prices=[100.0,101.0,99.0,102.0,103.0,101.0,104.0,105.0,103.0,106.0,107.0,105.0,108.0,109.0,107.0,110.0,111.0,109.0,112.0,113.0,111.0];
round(realized_vol(prices, 20); digits=4)
# output

0.3143
```
"""
function realized_vol(prices::Vector{Float64}, window::Int=20)::Float64
  clean = filter(x -> !isnan(x) && x > 0, prices)
  length(clean) < window + 1 && return NaN
  rets = diff(log.(clean[(end - window):end]))
  σ = std(rets)
  isnan(σ) && return NaN
  return σ * sqrt(252)
end
