using DataFrames
using TimeSeries
using Dates
using Plots

export Asset,populate_ohlc

mutable struct Asset
    ticker::String  
    interval::StepRange{Date, <:Period}
    data
    function Asset(ticker::String,interval::StepRange{Date, <:Period}=Date(2010):Dates.Day(5):Date(2020))
        this = new()
        this.ticker = ticker
        this.interval= interval
        return this
    end

end
function populate_ohlc(asset::Asset,prop_func::Function=(x->rand()-0.5),start::Number=100,precision::Int=10)
    println(asset.interval)
    dates=asset.interval
    n = length(dates)
    function randomvalue(x,n::Int,f)
        arr::Vector{Number}=[x]
        while (length(arr)<n)
            old = last(arr)
            push!(arr,old+f(old))
        end
        return arr
    end
    function randomohlc(base::Number,n::Int,f,precision::Int)
        ohlc=[]
        lst=base
        while (length(ohlc)<n)
            arr=randomvalue(lst,precision,f)
            sortedarr=sort(arr)
            lst=last(arr)
            push!(ohlc,[first(arr),last(sortedarr),first(sortedarr),last(arr)])
        end
        return ohlc
    end
    asset.data= TimeArray(dates,transpose(hcat(randomohlc(start,n,prop_func,precision)...)),["Open","High","Low","Close"])
    return asset.data
end

function value(A::Asset)
    [last(A.data)["Close"]...][1][2]
end


# function plot(asset::Asset)
#     Plots.plot(asset.data)
# end



