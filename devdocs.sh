cd ./docs
julia make.jl
julia -e 'using Pkg; Pkg.activate(".."); using LiveServer; serve(dir="build")' &

# Keep checking until a service is running on port 8000
while ! netstat -tuln | grep -q ':8000 '; do
    sleep 1
done

xdg-open http://localhost:8000

