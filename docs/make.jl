#Used for building the Docs
push!(LOAD_PATH,"../src/")

using Pkg
Pkg.activate("..")

using Documenter, Qt

makedocs(sitename="Quant Documentation")
