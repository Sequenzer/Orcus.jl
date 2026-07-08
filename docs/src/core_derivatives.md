```@meta
CurrentModule = Orcus
CollapsedDocStrings = true
```

# Derivatives

A `Derivative` is a financial instrument whose value is derived from the
performance of an underlying asset, index, or other financial entity.
We model them via some `payoff` function that takes the underlying asset's price and returns the derivative's value.

## Types

```@docs
Derivative
@generate_derivative
Buy
Sell
LongCall
LongPut
ShortCall
ShortPut

```

## Methods

```@docs
name
u_value
payoff
value(D::Derivative)
abs_return(D::Derivative)
pct_return(D::Derivative)
log_return(D::Derivative)
price
instrument_key
print_props(D::Derivative)
```


```@index
Pages = ["core_derivatives.md"]
```
