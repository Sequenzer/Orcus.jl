using Orcus
using Plots
unicodeplots()

# ── Market setup ──────────────────────────────────────────────────────────────
# Three assets trimmed to their common history length.
# N=3, K=1 → residual space is 2D → correlation matrix has meaningful values.
let tickers = ["AAPL", "GOOG", "KO"]
    stocks = [load_stock(t) for t in tickers]
    n = minimum(length(s) for s in stocks)
    global M = market([s[(length(s) - n + 1):length(s)] for s in stocks])
end

# ── Strategy definition ───────────────────────────────────────────────────────
const TARGET_NOTIONAL = 1_000.0   # dollar value per leg
const MIN_SPREAD      = 0.001     # minimum residual spread to trade (avoids noise)

mutable struct PCAReversal <: Strategy
    broker::Broker
    market::Market
    pca::RollingPCA
    last_fit::Int
    fit_window::Int
    refit_every::Int
    nms::Vector{String}

    function PCAReversal(b::Broker)
        new(b, b.market,
            rolling_pca(120, 1),
            0, 120, 20,
            asset_names(b.market))
    end
end

@strategyMethods PCAReversal pca_reversal_next pca_reversal_init

function pca_reversal_init(s::PCAReversal) end

function pca_reversal_next(s::PCAReversal)
    n = length(s.market)
    n < s.fit_window + 1 && return

    if n - s.last_fit >= s.refit_every
        w = (n - s.fit_window + 1):n
        R_window = returns_matrix(s.market, w)
        fit!(s.pca, R_window)
        s.last_fit = n
    end

    !s.pca.fitted && return
    n < 2 && return

    R_now = returns_matrix(s.market, (n - 1):n)
    size(R_now, 2) < 1 && return

    r = R_now[:, 1]
    _, eps = project(s.pca, r)

    # Skip if signal is too weak
    maximum(eps) - minimum(eps) < MIN_SPREAD && return

    best  = argmin(eps)
    worst = argmax(eps)
    best == worst && return

    a_best  = s.market.data[s.nms[best]]
    a_worst = s.market.data[s.nms[worst]]

    # Dollar-neutral sizing: same notional on each leg regardless of share price
    qty_best  = max(1, floor(Int, TARGET_NOTIONAL / value(a_best)))
    qty_worst = max(1, floor(Int, TARGET_NOTIONAL / value(a_worst)))

    requestToCloseAll!(s.broker)
    placeOrder!(s.broker, Order(Buy(a_best),   qty_best))
    placeOrder!(s.broker, Order(Sell(a_worst), qty_worst))
end

# ── Run backtest ──────────────────────────────────────────────────────────────
bt = Backtest(M, PCAReversal, 10_000)
runTest(bt)

println(bt)
backtest_summary(bt)

# ── Analytics ─────────────────────────────────────────────────────────────────
println("\n=== Scree Plot (last fitted PCA) ===")
display(screeplot(bt.strategy.pca))

println("\n=== Equity Curve ===")
display(plot(bt))

println("\n=== Residual Correlation (full history) ===")
R_all = returns_matrix(bt.market)
_, E_all = project(bt.strategy.pca, R_all)
plot_residual_corr(E_all, bt.strategy.nms)
