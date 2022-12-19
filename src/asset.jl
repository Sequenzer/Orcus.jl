using DataFrames
using TimeSeries
using Dates
using Plots

mutable struct asset
    symbol
    data
    get_symbol
    create_random_OHLC
    function asset(symbol)
        this = new()
        this.symbol = symbol
        return this
    end

end
#Define Methods on Asset
function Base.getproperty(this::asset, s::Symbol)
    if s == :get_symbol
        function()
            return this.symbol
        end
    elseif s == :create_random_OHLC
        function(startdate,enddate,intervall)
                dates = startdate:intervall:enddate
                n = length(dates)
                ##Should be changeable
                base = rand()*100+50
                f = f = x -> rand()-0.5
                ## Random Walk through Dates
                function randomvalue(x,n::Int64,f)
                    arr::Vector{Float64}=[x]
                    while (length(arr)<n)
                        old = last(arr)
                        push!(arr,old+f(old))
                    end
                    return arr
                end
                this.data = TimeArray(dates, randomvalue(base,n,f))
                return this.data
        end
    elseif s == :method_2
        function(val_0, val_1)
            this.field_0 = val_0
            this.field_1 = val_1
        end
    else
        getfield(this, s)
    end
end

startdate = Date(2010)
enddate = Date(2020)
intervall = Dates.Day(5)

# dates=floor((enddate - startdate ) / interval)
# arr = collect(1:dates)
# map(x -> startdate+x*intervall,arr)


ex = asset("Test") 

ex.get_symbol()
ta = ex.create_random_OHLC(startdate,enddate,intervall)
plot(ta)
