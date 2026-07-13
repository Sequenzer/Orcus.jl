using Test
using Orcus

using Dates
using Random
using RecipesBase  # recipes are exercised renderer-free via apply_recipe
using Statistics
using Tables

@testset verbose = true "Orcus.jl" begin
  include("Core/Asset.jl")
  include("Core/Utils.jl")
  include("Core/Derivative.jl")
  include("Core/Market.jl")
  include("Core/Resample.jl")
  include("Core/Cost.jl")
  include("Core/Margin.jl")
  include("Core/Position.jl")
  include("Core/Trade.jl")
  include("Core/Order.jl")
  include("Core/Strategy.jl")
  include("Core/Broker.jl")
  include("Core/Netting.jl")
  include("Core/Batch.jl")
  include("Core/FX.jl")
  include("Core/Tables.jl")
  include("Analytics/Stats.jl")
  include("Lib/Stocks.jl")
  include("allocations.jl")
end
