


IncompleteVector = AbstractVector{<:Union{<:Real, Missing}}






"""
    randomValue(x::Real,n::Int,prop_func::Function)

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
    
function randomValue(x::Real,n::Int,f::Function)
    arr::Vector{Real}=[x]
    while (length(arr)<n)
        old = last(arr)
        push!(arr,old+f(old))
    end
    return arr
end

