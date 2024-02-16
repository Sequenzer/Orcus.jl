using Test
using Qt

using Dates


@testset verbose = true "Qt.jl" begin
    include("Asset.jl")
    include("Utils.jl")
    include("Strategy.jl")
end

