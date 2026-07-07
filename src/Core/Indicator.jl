
"""
    IndicatorGenerator(f::Function, window::Int)

A rolling-window indicator: applies `f` to each `window`-length slice of a data series.

```jldoctest
SMA10=IndicatorGenerator(simple_average,10)
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
    simple_average(data::DataPoint)

Mean of `data`, ignoring NaN entries.

```jldoctest
simple_average([1.0,NaN,3.0,4.0])
# output

2.6666666666666665
```
"""
simple_average(data::DataPoint)::Float64 = mean(filter(!isnan, data))
