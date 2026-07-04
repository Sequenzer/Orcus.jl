using Orcus
using Plots
unicodeplots()

# ── Universe ──────────────────────────────────────────────────────────────────
# 10 stocks across consumer, energy, industrial, financial sectors.
# All have ~12k daily bars; trim to the shortest for a clean aligned panel.
UNIVERSE = ["KO", "MO", "DIS",        # consumer
            "MRO", "HAL",              # energy
            "BA", "GE", "HON",         # industrials
            "AXP", "USB"]              # financials

println("Loading universe: ", join(UNIVERSE, ", "))
raw = load_stocks(UNIVERSE)
n_common = minimum(length(raw.data[t]) for t in asset_names(raw))
M = trim_to_length(raw, n_common)
println("Aligned to $n_common bars × $(length(M.data)) assets\n")

# ── Strategy ──────────────────────────────────────────────────────────────────
const N_FACTORS   = 3    # market + 2 sector factors
const FIT_WINDOW  = 252  # ~1 year of daily bars
const REFIT_EVERY = 63   # refit quarterly
const N_LONG      = 3    # long top-N by residual signal
const N_SHORT     = 3    # short bottom-N

mutable struct PCAMulti <: Strategy
    broker::Broker
    market::Market
    pca::RollingPCA
    last_fit::Int
    nms::Vector{String}

    function PCAMulti(b::Broker)
        new(b, b.market,
            rolling_pca(FIT_WINDOW, N_FACTORS),
            0,
            asset_names(b.market))
    end
end

@strategy_methods PCAMulti pca_multi_next pca_multi_init

function pca_multi_init(s::PCAMulti) end

function pca_multi_next(s::PCAMulti)
    n = length(s.market)
    n < FIT_WINDOW + 1 && return

    # Quarterly PCA refit
    if n - s.last_fit >= REFIT_EVERY
        R_win = returns_matrix(s.market, (n - FIT_WINDOW + 1):n)
        fit!(s.pca, R_win)
        s.last_fit = n
    end

    !s.pca.fitted && return
    n < 2 && return

    # Current bar residuals
    R_now = returns_matrix(s.market, (n - 1):n)
    size(R_now, 2) < 1 && return
    _, eps = project(s.pca, R_now[:, 1])

    # Rank: buy most-negative (underperformed factor → mean-revert up),
    #       sell most-positive (outperformed → mean-revert down)
    ranked = sortperm(eps)           # ascending residual
    longs  = ranked[1:N_LONG]
    shorts = ranked[end-N_SHORT+1:end]

    request_to_close_all!(s.broker)

    # Dollar-approximate sizing: allocate 1/6 of equity per leg
    equity = s.broker.cash + sum(value(p) for p in values(s.broker.portfolio); init=0.0)
    budget = max(0.0, equity / (N_LONG + N_SHORT))

    for i in longs
        a = s.market.data[s.nms[i]]
        px = value(a)
        px <= 0 && continue
        qty = max(1, floor(Int, budget / px))
        place_order!(s.broker, Order(Buy(a), qty))
    end
    for i in shorts
        a = s.market.data[s.nms[i]]
        px = value(a)
        px <= 0 && continue
        qty = max(1, floor(Int, budget / px))
        place_order!(s.broker, Order(Sell(a), qty))
    end
end

# ── Run ───────────────────────────────────────────────────────────────────────
bt = Backtest(M, PCAMulti, 100_000)
run_test(bt)

# ── Results ───────────────────────────────────────────────────────────────────
backtest_summary(bt)

println("\n=== Scree Plot — last fitted PCA ===")
display(screeplot(bt.strategy.pca))

println("\n=== Factor Loadings (each row = asset, each col = factor) ===")
nms = bt.strategy.nms
V   = bt.strategy.pca.eigvecs          # [N × K]
println(rpad("", 6), join(lpad.("F$k", 9) for k in 1:size(V, 2)))
for (i, nm) in enumerate(nms)
    print(rpad(nm, 6))
    for j in 1:size(V, 2)
        print(lpad(round(V[i, j]; digits=3), 9))
    end
    println()
end

println("\n=== Residual Correlation (full history) ===")
R_all = returns_matrix(bt.market)
_, E_all = project(bt.strategy.pca, R_all)
plot_residual_corr(E_all, nms)

println("\n=== Equity Curve ===")
display(plot(bt))
