using Test
using Orcus

using Dates
using RecipesBase  # recipes are exercised renderer-free via apply_recipe
using Tables



@testset verbose = true "Orcus.jl" begin
    include("Core/Asset.jl")
    include("Core/Utils.jl")
    include("Core/Derivative.jl")
    include("Core/Market.jl")
    include("Core/Cost.jl")
    include("Core/Position.jl")
    include("Core/Trade.jl")
    include("Core/Order.jl")
    include("Core/Strategy.jl")
    include("Core/Broker.jl")
    include("Core/Netting.jl")
    include("Core/Batch.jl")
    include("Core/Tables.jl")
    #include("Strategy.jl")
end

