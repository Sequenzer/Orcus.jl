```@meta
CurrentModule = Orcus
CollapsedDocStrings = true
```


# Market data

`Asset` and `Market` are the price-data containers: an `Asset` holds one instrument's OHLC
history plus any attached indicators, a `Market` collects several assets, and `advance_to!`
moves the shared bar cursor by re-slicing each asset's visible window as a `SubArray` — no
copy per bar.

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
value(A::Asset)
apply_indicator
calculate_indicator
IndicatorGenerator
simple_average
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

## Synthetic data

Lower-level building blocks behind `rand_ohlc`, useful for stitching together custom
price paths (e.g. calm → crash → recovery regimes) for strategy stress-testing.

```@docs
DataPoint
DataSeries
data_series
gbm_path
gbm_path_segments
gbm_step
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
set_fx!
```

## Time axis

An optional shared `Market.axis::Vector{DateTime}` labels bars for loaders, collectors,
and annualization; the engine clock itself stays an integer bar index and never reads it.

```@docs
set_axis!
timestamp
bar_of
has_axis
resample
```

# Index

```@index
Pages = ["core_data.md"]
```
