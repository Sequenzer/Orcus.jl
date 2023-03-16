#Used for building the Docs
push!(LOAD_PATH,"../src/")

using Documenter, Qt

makedocs(sitename="Quant Documentation")
