# Used for building the Docs.
# Run with the docs environment: julia --project=docs docs/make.jl
using Pkg
Pkg.activate(@__DIR__)
Pkg.develop(path = joinpath(@__DIR__, ".."))
Pkg.instantiate()

using Documenter, Orcus

makedocs(sitename = "Orcus.jl")
