export
    trades_table,
    positions_table,
    equity_table,
    cashflows_table

const TradeRow = @NamedTuple{bar::Int, ticker::String, kind::Symbol,
    strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing},
    volume::Float64, price::Float64, delta_cash::Float64}

function _trade_row(T::Trade)
    key = instrument_key(T.derivative)
    return TradeRow((T.date, key.ticker, key.kind, key.strike, key.expiry,
                      T.volume, Float64(price(T)), T.delta_cash))
end

"""
    trades_table(B::Broker)

Every fill in `B.history` as a Tables.jl row table.
"""
trades_table(B::Broker) = TradeRow[_trade_row(T) for T in B.history]

const PositionRow = @NamedTuple{ticker::String, kind::Symbol,
    strike::Union{Float64,Nothing}, expiry::Union{Int,Nothing},
    net_qty::Float64, avg_cost::Float64, realized_pnl::Float64}

_position_row((key, P)) = PositionRow((key.ticker, key.kind, key.strike, key.expiry,
                                        P.net_qty, P.avg_cost, P.realized_pnl))

"""
    positions_table(B::Broker)

Every open position in `B.portfolio` as a Tables.jl row table.
"""
positions_table(B::Broker) =
    PositionRow[_position_row(kp) for kp in zip(keys(B.portfolio), values(B.portfolio))]

const EquityRow = @NamedTuple{bar::Int, equity::Float64}

"""
    equity_table(B::Broker)

The equity curve (`B.equity_history`) as a Tables.jl row table.
"""
equity_table(B::Broker) = EquityRow[(bar=i, equity=e) for (i, e) in enumerate(B.equity_history)]

const CashflowRow = @NamedTuple{bar::Int, cash::Float64}

"""
    cashflows_table(B::Broker)

The cash balance over time (`cash_history`) as a Tables.jl row table.
"""
cashflows_table(B::Broker) = CashflowRow[(bar=d, cash=Float64(c)) for (d, c) in cash_history(B)]
