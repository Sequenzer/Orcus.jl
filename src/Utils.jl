
"""
    randomValue(x::Number,n::Int,prop_func::Function)

Generates a Vector of n random values around x based on a propability function.

# Example
```jldoctests
x=100
n=3
f=k->k
randomValue(x,n,f)

# output
[100,200,400]
```
"""
    
function randomValue(x::Number,n::Int,f::Function)
    arr::Vector{Number}=[x]
    while (length(arr)<n)
        old = last(arr)
        push!(arr,old+f(old))
    end
    return arr
end

