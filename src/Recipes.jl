# Plotting via RecipesBase.
#
# Orcus describes *how* its types plot without depending on any renderer. Load a renderer to
# draw them, e.g. `using Plots; gr()` for graphics or `using Plots; unicodeplots()` for the
# terminal/REPL, then call `plot(asset)`, `plot(broker)`, `screeplot(pca)`, etc.
#
# RecipesBase owns the `plot`/`plot!` names (Plots.jl implements them); these recipes only add
# `apply_recipe` methods, so Orcus must not define or export `plot`/`plot!` itself.

using RecipesBase

# --- Asset: price/indicator series ----------------------------------------------------------
@recipe function f(A::Asset, data_key::String="Close")
  row = A._idx[data_key]
  series = filter(!isnan, A.data[row, :])
  seriestype --> :line
  xguide --> "Time"
  yguide --> "Value"
  title --> "$(A.ticker) $(data_key)"
  label --> "$(A.ticker) $(data_key)"
  1:length(series), series
end

# --- Broker / Backtest: equity curve --------------------------------------------------------
@recipe function f(B::Broker)
  eq = B.equity_history
  seriestype --> :line
  xguide --> "Bar"
  yguide --> "Equity"
  title --> "Equity curve"
  label --> "Equity"
  1:length(eq), eq
end

@recipe f(BT::Backtest) = BT.broker

# --- Derivative: payoff diagram -------------------------------------------------------------
@recipe function f(D::Derivative)
  v = u_value(D)
  x = range(v - v / 2, v + v / 2)
  seriestype --> :line
  xguide --> "Underlying"
  yguide --> "Payoff"
  title --> D.underlying.ticker * ", " * name(D)
  label --> name(D)
  x, payoff.(Ref(D), x) .- D.price
end

# --- PCA scree plot -------------------------------------------------------------------------
@userplot ScreePlot

@recipe function f(sp::ScreePlot)
  pca = sp.args[1]
  ev = explained_variance(pca)
  labels = ["Factor $k" for k in 1:length(ev)]
  values = round.(ev .* 100; digits=1)
  seriestype --> :bar
  xguide --> "Explained variance (%)"
  title --> "PCA Scree Plot"
  legend --> false
  labels, values
end
