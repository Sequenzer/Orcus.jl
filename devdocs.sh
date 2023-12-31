cd ./docs
julia make.jl
julia -e 'using Pkg; Pkg.activate(".."); using LiveServer; serve(dir="build")'

