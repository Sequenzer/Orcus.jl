export
  CostModel,
  NoCost,
  FlatCost,
  transaction_cost

"""
    CostModel

Abstract type for transaction-cost models. A cost model maps the gross notional of a
fill to a `(commission, slippage)` pair, both expressed as positive cash amounts that
always *worsen* the fill (commission is paid, slippage is an adverse price move).

Implement a new model by adding a `transaction_cost(::MyCostModel, notional)` method.
"""
abstract type CostModel end

"""
    NoCost()

Frictionless fills — zero commission, zero slippage. The default so existing backtests
behave exactly as before.
"""
struct NoCost <: CostModel end

"""
    FlatCost(; commission_pct=0.0, slippage_bps=0.0)

Flat proportional cost model.

- `commission_pct` — commission as a fraction of `|notional|` (e.g. `0.001` = 10 bps).
- `slippage_bps`   — adverse fill as basis points of `|notional|` (e.g. `5.0` = 5 bps).

Both are charged on every fill regardless of trade direction.
"""
struct FlatCost <: CostModel
  commission_pct::Float64
  slippage_bps::Float64
end

FlatCost(; commission_pct::Real=0.0, slippage_bps::Real=0.0) =
  FlatCost(Float64(commission_pct), Float64(slippage_bps))

"""
    transaction_cost(model::CostModel, notional::Real) -> (commission, slippage)

Return the `(commission, slippage)` cash amounts for a fill of the given gross
`notional`. Both values are non-negative.
"""
transaction_cost(::NoCost, notional::Real) = (commission=0.0, slippage=0.0)

function transaction_cost(cm::FlatCost, notional::Real)
  base = abs(Float64(notional))
  return (commission=cm.commission_pct * base,
    slippage=cm.slippage_bps / 1e4 * base)
end
