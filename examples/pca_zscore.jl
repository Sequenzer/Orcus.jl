using Orcus
using Plots
unicodeplots()
using Statistics

let tickers = ["KO","MO","DIS","MRO","HAL","BA","GE","HON","AXP","USB"]
    raw = load_stocks(tickers)
    global M = trim_to_length(raw, 5_000)
end

# ── Strategy ──────────────────────────────────────────────────────────────────
#
# PCA Cross-Sectional Statistical Arbitrage
# -----------------------------------------
# 1. Rolling PCA (K=2 factors) to extract idiosyncratic residuals.
# 2. Every `hold` bars, compute each asset's CUMULATIVE idiosyncratic return
#    over the last `hold` bars by projecting the return block through PCA.
# 3. Cross-sectionally rank all N assets by their cumulative residual.
# 4. Go LONG the bottom-K underperformers (contrarian: expect catch-up).
#    Go SHORT the top-K outperformers (contrarian: expect pull-back).
# 5. Close all positions, reopen the new basket, repeat.
#
# Cross-sectional ranking is more robust than per-asset z-scores because:
#   - Equal long/short exposure by construction (dollar-neutral).
#   - The signal is relative performance, not an absolute threshold.
#   - No rolling-buffer normalization issues.
#
# Uses Orcus functions: asset_names, returns_matrix, position_direction,
#   request_to_close_all!, place_order!, cross_section_rank.

mutable struct PCAStatArb <: Strategy
    broker::Broker
    market::Market
    pca::RollingPCA
    last_fit::Int
    fit_window::Int
    refit_every::Int
    nms::Vector{String}
    last_rebalance::Int
    hold::Int              # bars between rebalances
    n_legs::Int            # longs AND shorts per side
    target_notional::Float64

    function PCAStatArb(b::Broker)
        nms = asset_names(b.market)
        new(b, b.market,
            rolling_pca(120, 2),
            0, 120, 60, nms,
            0, 20, 2, 2_000.0)
    end
end

@strategy_methods PCAStatArb pca_statarb_next pca_statarb_init

function pca_statarb_init(s::PCAStatArb) end

function pca_statarb_next(s::PCAStatArb)
    n = length(s.market)
    n < s.fit_window + 1 && return

    # Periodic PCA refit
    if n - s.last_fit >= s.refit_every
        w = (n - s.fit_window + 1):n
        fit!(s.pca, returns_matrix(s.market, w))
        s.last_fit = n
    end
    !s.pca.fitted && return

    # Only act on rebalance bars
    n - s.last_rebalance < s.hold && return
    s.last_rebalance = n

    # Close the current basket
    request_to_close_all!(s.broker)

    # Cumulative idiosyncratic return over the holding window
    lo  = max(1, n - s.hold + 1)
    R   = returns_matrix(s.market, lo:n)
    size(R, 2) < 1 && return
    _, E = project(s.pca, R)           # E : [N × T] residual matrix
    cum_resid = vec(sum(E, dims=2))    # sum across time → [N]

    # Cross-sectional rank (1 = most negative cumulative residual)
    ranks = cross_section_rank(cum_resid)   # uses Orcus's cross_section_rank

    # Long the n_legs best performers  (highest residual → momentum continuation)
    # Short the n_legs worst performers (lowest residual  → momentum continuation)
    for (i, nm) in enumerate(s.nms)
        a   = s.market.data[nm]
        qty = max(1, floor(Int, s.target_notional / value(a)))
        if ranks[i] > length(s.nms) - s.n_legs
            place_order!(s.broker, Order(Buy(a), qty))
        elseif ranks[i] <= s.n_legs
            place_order!(s.broker, Order(Sell(a), qty))
        end
    end
end

# ── Run ───────────────────────────────────────────────────────────────────────
bt = Backtest(M, PCAStatArb, 50_000)
run_test(bt)

# ── Results ───────────────────────────────────────────────────────────────────
backtest_summary(bt)

plot(bt)

screeplot(bt.strategy.pca)

R_all = returns_matrix(bt.market)
_, E_all = project(bt.strategy.pca, R_all)
plot_residual_corr(E_all, bt.strategy.nms)
