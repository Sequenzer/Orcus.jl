
module Qt

using Pkg
using Dates
using Random
using Statistics
using Printf
using UnicodePlots
using DataStructures
using DataFrames
using CSV
using JSON

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
include("Core/Strategy.jl")
include("Core/Backtest.jl")

include("Lib/Strategies.jl")
include("Lib/Stocks.jl")

include("Live/core.jl")
include("Live/live_trader.jl")

const PROJECT_TOML = Pkg.TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
const VERSION_NUMBER = VersionNumber(PROJECT_TOML["version"])

function __init__()
    println(stderr, "$(PROJECT_TOML["name"]) v$(VERSION_NUMBER) initialized.")
    if isinteractive()
        try
            ensure_connected(verbose=true)
        catch e
            @warn "Qt: auto-connect failed: $e\n  Run ensure_connected() to retry."
        end
    end
end




end



