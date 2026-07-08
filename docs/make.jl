# Used for building the Docs.
# Run with the docs environment: julia --project=docs docs/make.jl
using Pkg
Pkg.activate(@__DIR__)
Pkg.develop(path=joinpath(@__DIR__, ".."))
Pkg.instantiate()

using Documenter, Orcus

DocMeta.setdocmeta!(Orcus, :DocTestSetup, :(using Orcus, Random); recursive=true)

makedocs(
  sitename="Orcus.jl",
  modules=[Orcus],
  format=Documenter.HTML(prettyurls=get(ENV, "CI", nothing) == "true"),
  warnonly=[:missing_docs, :doctest],
  pages=[
    "Home" => "index.md",
    "Tutorial" => "tutorial.md",
    "Examples" => "examples.md",
    "Core" => [
      "Market data" => "core_data.md",
      "Orders & accounting" => "core_accounting.md",
      "Derivatives" => "core_derivatives.md",
      "Strategy authoring" => "core_strategy.md",
      "Backtesting" => "core_backtest.md",
    ],
    "Lib" => "lib.md",
    "Analytics" => "analytics.md",
  ],
)

deploydocs(
  repo="github.com/Sequenzer/Orcus.jl",
  devbranch="main",
)
