
module Orcus

using Dates
using Random
using Statistics
using LinearAlgebra
using Printf
using Tables

export
  Dates,
  Random,
  Statistics,
  Tables

include("Core/Utils.jl")
include("Core/Indicator.jl")
include("Core/Asset.jl")
include("Core/Derivative.jl")
include("Core/Market.jl")
include("Core/Resample.jl")
include("Core/Order.jl")
include("Core/Trade.jl")
include("Core/Cost.jl")
include("Core/Margin.jl")
include("Core/Position.jl")
include("Core/Portfolio.jl")
include("Core/Broker.jl")
include("Core/Strategy.jl")
include("Core/Backtest.jl")
include("Core/Tables.jl")
include("Core/Batch.jl")

include("Lib/Strategies.jl")
include("Lib/Stocks.jl")

include("Analytics/PCA.jl")
include("Analytics/Rolling.jl")
include("Analytics/Stats.jl")
include("Analytics/Indicators.jl")
include("Analytics/Options.jl")

include("Recipes.jl")

function __init__()
  println(stderr, "Orcus v$(pkgversion(@__MODULE__)) initialized.")
end

end
