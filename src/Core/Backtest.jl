
export Backtest,
  run_test,
  process_day!

"""

    Backtest(market::Market, strategy::Strategy, cash::Real=1000)

Backtest a strategy on a market.

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
T = Backtest(M,CrossOverStrategy,1000)
run_test(T)

# output

Backtest of CrossOverStrategy with 375.71 funds on market comprised of 2 assets.

```
"""
mutable struct Backtest{T<:Strategy}
  market::Market
  broker::Broker
  strategy::T
  completed::Bool
  function Backtest(market::Market, strategy::Type, cash::Real=1000;
    params=(;), cost_model::CostModel=NoCost())
    this = new{strategy}()
    this.market = market
    this.broker = Broker(market, cash; cost_model=cost_model)
    this.strategy = strategy(this.broker; params...)
    this.completed = false
    return this
  end
end

backtest(
  market::Market,
  strategy::Type,
  cash::Real=1000;
  params=(;),
  cost_model::CostModel=NoCost(),
) =
  Backtest(market, strategy, cash; params=params, cost_model=cost_model)

@inline function process_day!(BT::Backtest)
  process_all!(BT.broker)
  next(BT.strategy)
  return nothing
end
function run_test(BT::Backtest)
  if BT.completed
    error("Backtest already completed")
  end
  # Initialize strategy (indicators computed here, with all bars visible)
  init(BT.strategy)
  B = BT.broker
  M = B.market
  full = 0
  for a in M.assets
    full = max(full, size(a.data, 2))
  end
  sizehint!(B.equity_history, full)   # preallocate — per-bar push never reallocates

  for i in 1:full
    advance_to!(M, i)        # cursor advance — no copy, no per-bar allocation
    process_day!(BT)
  end
  BT.completed = true
  return BT
end

Base.show(io::IO, BT::Backtest) = print(io,
  """
  Backtest of $(typeof(BT.strategy)) with $(round(BT.broker.cash;digits=2)) funds on market comprised of $(length(keys(BT.market.data))) assets.
  """)
