
"""
    sharpe_ratio(equity; rf=0.0, periods_per_year=252) -> Float64

Annualized Sharpe ratio computed from an equity curve.
`rf` is the annualized risk-free rate (default 0). Returns `NaN` if there
is insufficient data or zero volatility.
"""
function sharpe_ratio(equity::Vector{<:Real};
  rf::Float64=0.0,
  periods_per_year::Int=252)
  length(equity) < 2 && return NaN
  # filter out leading zeros / warm-up period
  first_nonzero = findfirst(!=(0), equity)
  isnothing(first_nonzero) && return NaN
  eq = Float64.(equity[first_nonzero:end])
  length(eq) < 2 && return NaN

  rets = diff(eq) ./ eq[1:(end - 1)]
  μ = mean(rets) - rf / periods_per_year
  σ = std(rets)
  σ == 0 && return NaN
  return μ / σ * sqrt(periods_per_year)
end

"""
    max_drawdown(equity) -> Float64

Maximum peak-to-trough drawdown as a fraction (0 to 1).
"""
function max_drawdown(equity::Vector{<:Real})
  isempty(equity) && return 0.0
  peak = Float64(first(equity))
  mdd = 0.0
  for v in equity
    fv = Float64(v)
    peak = max(peak, fv)
    peak > 0 && (mdd = max(mdd, (peak - fv) / peak))
  end
  return mdd
end

"""
    backtest_summary(bt::Backtest)

Print a concise performance summary for a completed backtest.
"""
function backtest_summary(bt::Backtest)
  eq = bt.broker.equity_history
  isempty(eq) && (println("No equity history."); return nothing)

  start_eq = Float64(first(eq))
  end_eq = Float64(last(eq))
  total_ret = (end_eq - start_eq) / start_eq * 100

  sr = sharpe_ratio(eq)
  mdd = max_drawdown(eq) * 100

  n_trades = length(bt.broker.history)
  n_bars = length(eq)

  println("="^44)
  @printf "  Strategy : %s\n" string(typeof(bt.strategy))
  @printf "  Bars     : %d\n" n_bars
  @printf "  Trades   : %d\n" n_trades
  @printf "  Start    : %.2f\n" start_eq
  @printf "  End      : %.2f\n" end_eq
  @printf "  Return   : %+.2f%%\n" total_ret
  @printf "  Sharpe   : %.3f\n" isnan(sr) ? 0.0 : sr
  @printf "  Max DD   : %.2f%%\n" mdd
  println("="^44)
end

"""
    cross_section_rank(v) -> Vector{Int}

Integer ranks 1…N (1 = smallest value). Useful for factor-based long/short construction.
"""
cross_section_rank(v::Vector{Float64}) = sortperm(sortperm(v))

"""
    cross_section_zscore(v) -> Vector{Float64}

Normalize a cross-sectional score vector to zero mean and unit variance.
Returns zeros if the vector has zero standard deviation.
"""
function cross_section_zscore(v::Vector{Float64})
  mu, sigma = mean(v), std(v)
  sigma < 1e-10 && return zeros(length(v))
  return (v .- mu) ./ sigma
end

"""
    sortino_ratio(equity; rf=0.0, periods_per_year=252) -> Float64

Annualized Sortino ratio: like Sharpe but penalises downside volatility only.
Downside deviation = sqrt(mean of squared negative excess returns).
"""
function sortino_ratio(equity::Vector{<:Real};
  rf::Float64=0.0,
  periods_per_year::Int=252)
  length(equity) < 2 && return NaN
  first_nonzero = findfirst(!=(0), equity)
  isnothing(first_nonzero) && return NaN
  eq = Float64.(equity[first_nonzero:end])
  length(eq) < 2 && return NaN
  rets = diff(eq) ./ eq[1:(end - 1)]
  excess = rets .- rf / periods_per_year
  μ = mean(excess)
  σ_d = sqrt(mean(min(r, 0.0)^2 for r in excess))
  σ_d < 1e-10 && return NaN
  return μ / σ_d * sqrt(periods_per_year)
end

"""
    calmar_ratio(equity; periods_per_year=252) -> Float64

Annualized return divided by maximum drawdown.
"""
function calmar_ratio(equity::Vector{<:Real}; periods_per_year::Int=252)
  length(equity) < 2 && return NaN
  first_nonzero = findfirst(!=(0), equity)
  isnothing(first_nonzero) && return NaN
  eq = Float64.(equity[first_nonzero:end])
  mdd = max_drawdown(eq)
  mdd < 1e-10 && return NaN
  n = length(eq)
  ann_ret = (eq[end] / eq[1])^(periods_per_year / n) - 1
  return ann_ret / mdd
end

"""
    profit_factor(equity) -> Float64

Gross profit / gross loss computed from the equity-curve return series.
Returns `Inf` if there are no losing bars.
"""
function profit_factor(equity::Vector{<:Real})
  length(equity) < 2 && return NaN
  rets = diff(Float64.(equity))
  gains = sum(r for r in rets if r > 0; init=0.0)
  losses = sum(abs(r) for r in rets if r < 0; init=0.0)
  losses < 1e-10 && return Inf
  return gains / losses
end

"""
    win_rate_bars(equity) -> Float64

Fraction of bars in which the equity curve increased (a rough proxy for
trade-level win rate when the strategy has one position at a time).
"""
function win_rate_bars(equity::Vector{<:Real})
  length(equity) < 2 && return NaN
  rets = diff(Float64.(equity))
  return count(>(0), rets) / length(rets)
end

"""
    annualized_return(equity; periods_per_year=252) -> Float64

Compound Annual Growth Rate (CAGR): the constant yearly return that
would produce the same total growth as the equity curve.
"""
function annualized_return(equity::Vector{<:Real}; periods_per_year::Int=252)
  length(equity) < 2 && return NaN
  first_nonzero = findfirst(!=(0), equity)
  isnothing(first_nonzero) && return NaN
  eq = Float64.(equity[first_nonzero:end])
  eq[1] <= 0 && return NaN
  n = length(eq)
  return (eq[end] / eq[1])^(periods_per_year / n) - 1
end

"""
    value_at_risk(equity; confidence=0.95) -> Float64

Daily Value at Risk at the given confidence level: the return threshold
such that losses exceed this level on `(1-confidence)` fraction of days.
Returned as a negative number (a loss).
"""
function value_at_risk(equity::Vector{<:Real}; confidence::Float64=0.95)
  length(equity) < 2 && return NaN
  eq = Float64.(equity)
  rets = diff(eq) ./ eq[1:(end - 1)]
  return quantile(rets, 1.0 - confidence)
end

"""
    cvar(equity; confidence=0.95) -> Float64

Conditional Value at Risk (Expected Shortfall): the mean return on the
worst `(1-confidence)` fraction of days. More conservative than VaR.
Returned as a negative number.
"""
function cvar(equity::Vector{<:Real}; confidence::Float64=0.95)
  length(equity) < 2 && return NaN
  eq = Float64.(equity)
  rets = diff(eq) ./ eq[1:(end - 1)]
  var = quantile(rets, 1.0 - confidence)
  tail = filter(<=(var), rets)
  isempty(tail) && return var
  return mean(tail)
end

"""
    omega_ratio(equity; threshold=0.0, periods_per_year=252) -> Float64

Omega ratio: probability-weighted ratio of gains to losses above/below
`threshold` (annualised). Values > 1 indicate more gain than loss.
Unlike Sharpe, Omega uses the full return distribution (captures skew/kurtosis).
"""
function omega_ratio(equity::Vector{<:Real};
  threshold::Float64=0.0,
  periods_per_year::Int=252)
  length(equity) < 2 && return NaN
  eq = Float64.(equity)
  rets = diff(eq) ./ eq[1:(end - 1)]
  daily_τ = threshold / periods_per_year
  gains = sum(max(r - daily_τ, 0.0) for r in rets; init=0.0)
  losses = sum(max(daily_τ - r, 0.0) for r in rets; init=0.0)
  losses < 1e-10 && return Inf
  return gains / losses
end

"""
    ulcer_index(equity) -> Float64

Ulcer Index: root mean square of all percentage drawdowns from peak.
Captures both depth and duration of drawdowns. Lower is better.
Useful as a risk denominator (Martin Ratio = CAGR / Ulcer Index).
"""
function ulcer_index(equity::Vector{<:Real})
  isempty(equity) && return 0.0
  eq = Float64.(equity)
  peak = first(eq)
  sum_sq = 0.0
  for v in eq
    peak = max(peak, v)
    dd = peak > 0 ? (peak - v) / peak * 100 : 0.0
    sum_sq += dd^2
  end
  return sqrt(sum_sq / length(eq))
end

"""
    information_ratio(equity, benchmark_equity; periods_per_year=252) -> Float64

Information Ratio: annualised active return divided by tracking error
vs a benchmark equity curve. Measures skill of active management.
Values above 0.5 are considered good; above 1.0 exceptional.
"""
function information_ratio(equity::Vector{<:Real},
  benchmark_equity::Vector{<:Real};
  periods_per_year::Int=252)
  (length(equity) < 2 || length(benchmark_equity) < 2) && return NaN
  r_s = diff(Float64.(equity)) ./ Float64.(equity[1:(end - 1)])
  r_b = diff(Float64.(benchmark_equity)) ./ Float64.(benchmark_equity[1:(end - 1)])
  n = min(length(r_s), length(r_b))
  excess = r_s[(end - n + 1):end] .- r_b[(end - n + 1):end]
  te = std(excess)
  te < 1e-10 && return NaN
  return mean(excess) / te * sqrt(periods_per_year)
end

"""
    bah_equity(market, cash; key="Close") -> Vector{Float64}

Compute the equity curve of an equal-weight buy-and-hold strategy
across all assets in `market` from bar 1 onward.
Useful as a benchmark for `information_ratio` and `compare_backtests`.
"""
function bah_equity(market::Market, cash::Real; key::String="Close")
  nms = asset_names(market)
  N = length(nms)
  n_bars = length(market)
  n_bars < 2 && return Float64[]

  # Pre-load and forward-fill each series so NaN weekends/holidays use last valid price
  price_series = Dict{String,Vector{Float64}}()
  shares = Dict{String,Float64}()
  for nm in nms
    raw = Float64.(market.data[nm][key])
    filled = copy(raw)
    last_valid = NaN
    for i in eachindex(filled)
      if !isnan(filled[i]) && filled[i] > 0
        last_valid = filled[i]
      elseif !isnan(last_valid)
        filled[i] = last_valid
      end
    end
    price_series[nm] = filled
    p0 = first(filter(x -> !isnan(x) && x > 0, filled))
    shares[nm] = isnan(p0) || p0 <= 0 ? 0.0 : (cash / N) / p0
  end

  eq = Vector{Float64}(undef, n_bars)
  for i in 1:n_bars
    total = 0.0
    for nm in nms
      p = i <= length(price_series[nm]) ? price_series[nm][i] : 0.0
      total += shares[nm] * (isnan(p) ? 0.0 : p)
    end
    eq[i] = total
  end
  return eq
end

"""
    infer_periods_per_year(axis) -> Int

Bars per year implied by the median spacing of a time axis: intraday bars scale by bars
per trading day, daily → 252, weekly → 52, monthly → 12, coarser → 1.
"""
function infer_periods_per_year(axis::Vector{DateTime})
  length(axis) < 2 && return 252
  day_ms = 86_400_000.0
  spacing = median(Dates.value.(diff(axis)))
  spacing <= 0 && return 252
  spacing < day_ms && return round(Int, 252 * day_ms / spacing)
  spacing <= 4 * day_ms && return 252
  spacing <= 10 * day_ms && return 52
  spacing <= 45 * day_ms && return 12
  return 1
end
infer_periods_per_year(M::Market) =
  M.axis === nothing ? 252 : infer_periods_per_year(M.axis)

"""
    extended_summary(bt::Backtest; benchmark=nothing, periods_per_year=inferred)

Print a detailed performance summary including CAGR, Sortino, Calmar,
Omega, VaR, CVaR, and Ulcer Index. Pass a `benchmark` equity curve
(e.g. from `bah_equity`) to also print the Information Ratio.
`periods_per_year` defaults to [`infer_periods_per_year`](@ref) of the market.
"""
function extended_summary(bt::Backtest; benchmark::Union{Vector{Float64},Nothing}=nothing,
  periods_per_year::Int=infer_periods_per_year(bt.broker.market))
  eq = bt.broker.equity_history
  isempty(eq) && (println("No equity history."); return nothing)

  start_eq = Float64(first(eq))
  end_eq = Float64(last(eq))
  total_ret = (end_eq - start_eq) / start_eq * 100
  cagr_val = annualized_return(eq; periods_per_year=periods_per_year) * 100

  sr = sharpe_ratio(eq; periods_per_year=periods_per_year)
  so = sortino_ratio(eq; periods_per_year=periods_per_year)
  cal = calmar_ratio(eq; periods_per_year=periods_per_year)
  om = omega_ratio(eq; periods_per_year=periods_per_year)
  mdd = max_drawdown(eq) * 100
  ui = ulcer_index(eq)
  pf = profit_factor(eq)
  wr = win_rate_bars(eq) * 100
  var_ = value_at_risk(eq) * 100
  cv = cvar(eq) * 100

  n_trades = length(bt.broker.history)
  n_bars = length(eq)
  years = n_bars / periods_per_year

  _f(x) = isnan(x) || isinf(x) ? 0.0 : x

  println("="^50)
  @printf "  Strategy  : %s\n" string(typeof(bt.strategy))
  @printf "  Bars      : %d  (%.1f yrs)\n" n_bars years
  @printf "  Trades    : %d\n" n_trades
  @printf "  Start     : %.2f\n" start_eq
  @printf "  End       : %.2f\n" end_eq
  println("-"^50)
  @printf "  Return    : %+.2f%%\n" total_ret
  @printf "  CAGR      : %+.2f%%\n" _f(cagr_val)
  println("-"^50)
  @printf "  Sharpe    : %.3f\n" _f(sr)
  @printf "  Sortino   : %.3f\n" _f(so)
  @printf "  Calmar    : %.3f\n" _f(cal)
  @printf "  Omega     : %.3f\n" _f(min(om, 999.0))
  @printf "  Ulcer Idx : %.3f\n" ui
  println("-"^50)
  @printf "  Max DD    : %.2f%%\n" mdd
  @printf "  VaR (95%%) : %.2f%%\n" _f(var_)
  @printf "  CVaR(95%%) : %.2f%%\n" _f(cv)
  println("-"^50)
  @printf "  Prof.Fac. : %.3f\n" _f(pf)
  @printf "  Win Rate  : %.1f%%\n" _f(wr)
  if !isnothing(benchmark)
    ir = information_ratio(eq, benchmark; periods_per_year=periods_per_year)
    @printf "  Info Ratio: %.3f\n" _f(ir)
  end
  println("="^50)
end

"""
    compare_backtests(bts, names; benchmark=nothing)

Print a side-by-side performance table for a collection of backtests.
Columns: Strategy | CAGR | Sharpe | Sortino | Calmar | Omega | VaR95 | MaxDD | Trades.
Pass `benchmark` (equity curve) to append an Information Ratio column.
"""
function compare_backtests(bts::Vector{<:Backtest}, names::Vector{String};
  benchmark::Union{Vector{Float64},Nothing}=nothing)
  @assert length(bts) == length(names)
  with_ir = !isnothing(benchmark)
  base_hdr = @sprintf "%-20s %8s %7s %7s %7s %7s %7s %7s %7s" "Strategy" "CAGR%" "Sharpe" "Sortino" "Calmar" "Omega" "VaR95%" "MaxDD%" "Trades"
  header = with_ir ? base_hdr * @sprintf(" %7s", "IR") : base_hdr
  println("="^length(header))
  println(header)
  println("-"^length(header))
  for (bt, nm) in zip(bts, names)
    eq = bt.broker.equity_history
    if isempty(eq)
      @printf "%-20s  (no data)\n" nm
      continue
    end
    _f(x) = isnan(x) || isinf(x) ? 0.0 : x
    cg = _f(annualized_return(eq) * 100)
    sr = _f(sharpe_ratio(eq))
    so = _f(sortino_ratio(eq))
    cal = _f(calmar_ratio(eq))
    om = _f(min(omega_ratio(eq), 99.0))
    var_ = _f(value_at_risk(eq) * 100)
    mdd = max_drawdown(eq) * 100
    tr = length(bt.broker.history)
    row = @sprintf "%-20s %+7.2f%% %7.3f %7.3f %7.3f %7.3f %7.2f%% %7.2f%% %7d" nm[1:min(
      end, 20
    )] cg sr so cal om var_ mdd tr
    if with_ir
      ir = _f(information_ratio(eq, benchmark))
      row *= @sprintf " %7.3f" ir
    end
    println(row)
  end
  println("="^length(header))
end
