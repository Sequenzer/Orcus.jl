```@meta
CurrentModule = Orcus
CollapsedDocStrings = true
```


# Market data

<!-- TODO: explain Asset/Market data model and zero-copy bar advancement -->

## Asset

The `Asset` type is the core data structure in Orcus. It represents a single
financial instrument and contains all of its historical
market data.

```@docs
Orcus.Asset
asset
names
rowindex
height
value
apply_indicator
calculate_indicator
shorten!
add_datapoint!
```

## Examples 

There are multiple ways to load data into Orcus.
You can also use randomly generated data provided via rand_ohlc, or the sample data in the `data` folder.

```@docs
rand_ohlc
available_stocks
load_stocks
load_stock
load_csvs
load_csv
GOOG
AAPL
```

## Market

The `Market` type is a collection of `Asset`s. It allows you to manage multiple assets and their data in a single structure.

```@docs
Market
market
height(M::Market)
add_asset!
advance_to!
shorten!(M::Market, U::UnitRange{Int})
asset_names
returns_matrix
trim_to_length(M::Market, n::Int)
```

# Index

```@index
Pages = ["core_data.md"]
```
