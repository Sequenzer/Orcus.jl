using Test
using Qt

using Dates



@testset verbose = true "Qt.jl" begin
    include("Core/Asset.jl")
    include("Core/Utils.jl")
    include("Core/Derivative.jl")
    include("Core/Market.jl")
    include("Core/Position.jl")
    include("Core/Trade.jl")
    include("Core/Order.jl")
    include("Core/Strategy.jl")
    include("Core/Broker.jl")
    #include("Strategy.jl")
end

