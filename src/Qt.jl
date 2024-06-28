
module Qt

using Pkg
using Dates
using Random
using Statistics
using UnicodePlots
using DataStructures


export 
    Dates,
    Random, 
    Statistics

include("Core/Utils.jl")
include("Core/Indicator.jl")
include("Core/Asset.jl")
include("Core/Derivative.jl")
include("Core/Market.jl")
include("Core/Order.jl")
include("Core/Trade.jl")
include("Core/Position.jl")
include("Core/Broker.jl")

include("Strategy.jl")
include("Lib/Strategies.jl")

include("Backtest.jl")


const PROJECT_TOML = Pkg.TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
const VERSION_NUMBER = VersionNumber(PROJECT_TOML["version"])

function __init__()
    otp ="""

    $(PROJECT_TOML["name"]) version $(VERSION_NUMBER) has been initialized....

    """
    println(otp)
end 




end



