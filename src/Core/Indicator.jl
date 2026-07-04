
export IndicatorGenerator,
  indicator_generator,
  simple_average

"""
    IndicatorGenerator(f::Function,window::Int)

# Fields
- f: computation function
- window: lookback size

# Example
```jldoctest
SMA10=indicator_generator(simple_average,10)
SMA10.window

# output
10
```
"""
mutable struct IndicatorGenerator
  calc_func::Function
  window::Int

  function IndicatorGenerator(
    calc_func::Function,
    window::Int=1,
  )
    this = new()
    this.calc_func = calc_func
    this.window = window
    return this
  end
end

indicator_generator(calc_func::Function, window::Int=1) =
  IndicatorGenerator(calc_func, window)

"""

simple_average([1,missing,3,4])

"""
simple_average(data::DataPoint)::Float64 = mean(filter(!isnan, data))
