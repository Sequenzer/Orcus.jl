# Portfolio — type-grouped position storage.
#
# Positions are segregated by concrete derivative type into homogeneously-typed `Group{D}`s.
# Two reasons:
#   1. No boxing — iterating a `Group{D}` yields concrete `Position{D}`, so `value(P)` infers
#      `Float64` and the per-bar equity mark is allocation-free regardless of universe size.
#   2. No hashing at all — within a group, the live positions live in a contiguous
#      `Vector{Position{D}}` (cache-friendly, branch-predictable iteration); the *per-order*
#      key lookup is a linear scan of the parallel `keys` vector, which beats hashing an
#      `InstrumentKey` for realistic group sizes and is sparse relative to the bar loop.
# Every hot accessor is a **function barrier**: the built-in Buy/Sell groups are concretely
# typed fields (zero dispatch), open-world groups cost one dispatch each, and the inner loop
# is fully concrete either way.

"""
    Group{D}

Live positions for one concrete derivative type `D`. `positions` and `keys` are parallel
contiguous vectors (hot-path iteration); per-order key lookup is a linear scan of `keys` —
groups are small and orders are sparse relative to the bar loop, so the scan beats hashing
an `InstrumentKey` (whose `String` ticker dominates the hash). Removal is swap-pop.
"""
struct Group{D<:Derivative}
  positions::Vector{Position{D}}
  keys::Vector{InstrumentKey}
end
Group{D}() where {D<:Derivative} = Group{D}(Position{D}[], InstrumentKey[])

@inline function _find_key(g::Group, key::InstrumentKey)
  ks = g.keys
  @inbounds for i in eachindex(ks)
    ks[i] == key && return i
  end
  return 0
end

"""
    Portfolio()

Netted open positions, keyed by [`InstrumentKey`](@ref).

```jldoctest
isempty(Portfolio())
# output

true
```
"""
mutable struct Portfolio
  const buy::Group{Buy}
  const sell::Group{Sell}
  const others::Vector{Any}    # Group{D} objects for user-defined derivative types
  n::Int
  _acc::Float64
end

Portfolio() = Portfolio(Group{Buy}(), Group{Sell}(), Any[], 0, 0.0)

# ── hot path: equity mark ─────────────────────────────────────────────────────
"""
    total_value(pf::Portfolio)

Sum of `value(P)` over all open positions.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
A=B.market.assets[2];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
total_value(B.portfolio)
# output

22.50173968887256
```
"""
function total_value(pf::Portfolio)
  s = _group_sum(pf.buy) + _group_sum(pf.sell)
  isempty(pf.others) || (s += _others_value(pf))
  return s
end
@noinline function _others_value(pf::Portfolio)
  pf._acc = 0.0
  for g in pf.others
    _add_group_value!(pf, g)
  end
  return pf._acc
end
@inline _group_sum(g::Group{D}) where {D} = begin
  s = 0.0
  @inbounds for P in g.positions    # contiguous; P::Position{D} concrete → no box
    s += value(P)
  end
  s
end
# Open-world fallback: accumulate into `_acc` so the runtime-dispatched call returns `nothing`.
_add_group_value!(pf::Portfolio, g::Group{D}) where {D} = (
  pf._acc += _group_sum(g); nothing
)

"""
    total_loan(pf::Portfolio)

Sum of `P.loan` over all open positions — the aggregate broker-financed debt outstanding.
Always `0.0` unless positions were opened under a margin model with `initial_margin_pct < 1.0`.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
A=B.market.assets[2];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
total_loan(B.portfolio)
# output

0.0
```
"""
function total_loan(pf::Portfolio)
  s = _group_loan_sum(pf.buy) + _group_loan_sum(pf.sell)
  isempty(pf.others) || (s += _others_loan(pf))
  return s
end
@noinline function _others_loan(pf::Portfolio)
  pf._acc = 0.0
  for g in pf.others
    _add_group_loan!(pf, g)
  end
  return pf._acc
end
@inline _group_loan_sum(g::Group{D}) where {D} = begin
  s = 0.0
  @inbounds for P in g.positions
    s += P.loan
  end
  s
end
_add_group_loan!(pf::Portfolio, g::Group{D}) where {D} = (
  pf._acc += _group_loan_sum(g); nothing
)

"""
    total_abs_value(pf::Portfolio) -> Float64

Sum of `abs(value(P))` over all open positions — the gross open exposure a maintenance-margin
requirement is computed on. Same concretely-typed, allocation-free walk as [`total_value`](@ref).
"""
function total_abs_value(pf::Portfolio)
  s = _group_abs_sum(pf.buy) + _group_abs_sum(pf.sell)
  isempty(pf.others) || (s += _others_abs_value(pf))
  return s
end
@noinline function _others_abs_value(pf::Portfolio)
  pf._acc = 0.0
  for g in pf.others
    _add_group_abs_value!(pf, g)
  end
  return pf._acc
end
@inline _group_abs_sum(g::Group{D}) where {D} = begin
  s = 0.0
  @inbounds for P in g.positions
    s += abs(value(P))
  end
  s
end
_add_group_abs_value!(pf::Portfolio, g::Group{D}) where {D} = (
  pf._acc += _group_abs_sum(g); nothing
)

"""
    accrue_fees!(pf::Portfolio, rate::Float64) -> Float64

Charge `rate` against every position's financed exposure (`abs(value(P))` for a short,
`P.loan` for a financed long), debiting each position's `realized_pnl`, and return the total
fee. Same concretely-typed, allocation-free walk as [`total_value`](@ref).
"""
function accrue_fees!(pf::Portfolio, rate::Float64)
  total = _group_accrue!(pf.buy, rate) + _group_accrue!(pf.sell, rate)
  isempty(pf.others) || (total += _others_accrue!(pf, rate))
  return total
end
@noinline function _others_accrue!(pf::Portfolio, rate::Float64)
  pf._acc = 0.0
  for g in pf.others
    _add_group_accrue!(pf, g, rate)
  end
  return pf._acc
end
@inline _group_accrue!(g::Group{D}, rate::Float64) where {D} = begin
  total = 0.0
  @inbounds for P in g.positions
    v = value(P)
    exposure = v < 0.0 ? abs(v) : P.loan
    exposure == 0.0 && continue
    fee = exposure * rate
    P.realized_pnl -= fee
    total += fee
  end
  total
end
_add_group_accrue!(pf::Portfolio, g::Group{D}, rate::Float64) where {D} = (
  pf._acc += _group_accrue!(g, rate); nothing
)

# ── per-order: locate/create the typed group and position ─────────────────────
@inline _group!(pf::Portfolio, ::Type{Buy}) = pf.buy
@inline _group!(pf::Portfolio, ::Type{Sell}) = pf.sell
function _group!(pf::Portfolio, ::Type{D}) where {D<:Derivative}
  for g in pf.others
    g isa Group{D} && return g       # `isa` narrows g → type-stable return
  end
  g = Group{D}()
  push!(pf.others, g)
  return g
end

"""
    get_or_create!(pf, key, der::D) -> Position{D}

Return the live `Position{D}` for `key`, creating an empty one on first fill. Type-stable in
`D` (caller passes a concrete derivative), so the returned position is concrete.
"""
function get_or_create!(pf::Portfolio, key::InstrumentKey, der::D) where {D<:Derivative}
  g = _group!(pf, D)
  idx = _find_key(g, key)
  idx != 0 && return @inbounds g.positions[idx]
  P = Position(der)
  push!(g.positions, P)
  push!(g.keys, key)
  pf.n += 1
  return P
end

# Swap-pop a key out of its (typed) group; returns true if it was present.
function _drop_key!(pf::Portfolio, g::Group{D}, key::InstrumentKey) where {D}
  idx = _find_key(g, key)
  idx == 0 && return false
  last_i = length(g.positions)
  if idx != last_i
    @inbounds g.positions[idx] = g.positions[last_i]
    @inbounds g.keys[idx] = g.keys[last_i]
  end
  pop!(g.positions)
  pop!(g.keys)
  pf.n -= 1
  return true
end

"""
    drop!(pf, key, ::Type{D})

Remove the (now closed) position for `key` from its typed group. Used by `execute!`, which
knows the concrete `D` — no group scan.
"""
drop!(pf::Portfolio, key::InstrumentKey, ::Type{D}) where {D<:Derivative} = (
  _drop_key!(pf, _group!(pf, D), key); pf
)

# Generic delete (group unknown, e.g. close-outs) — scans groups; cold relative to the bar.
function Base.delete!(pf::Portfolio, key::InstrumentKey)
  _drop_key!(pf, pf.buy, key) && return pf
  _drop_key!(pf, pf.sell, key) && return pf
  for g in pf.others
    _del_from_group!(pf, g, key) && return pf
  end
  return pf
end
_del_from_group!(pf::Portfolio, g::Group{D}, key) where {D} = _drop_key!(pf, g, key)

"""
    set_all_close!(pf)

Flag every open position for close. Barrier per type-group.
"""
function set_all_close!(pf::Portfolio)
  _set_all_close!(pf.buy)
  _set_all_close!(pf.sell)
  for g in pf.others
    _set_all_close!(g)
  end
  return pf
end
_set_all_close!(g::Group{D}) where {D} = begin
  @inbounds for P in g.positions
    P.requestToClose = true
  end
end

"""
    set_ticker_close!(pf::Portfolio, ticker::String)

Flag every open position in `ticker` for close. Barrier per type-group.
"""
function set_ticker_close!(pf::Portfolio, ticker::String)
  _set_ticker_close!(pf.buy, ticker)
  _set_ticker_close!(pf.sell, ticker)
  for g in pf.others
    _set_ticker_close!(g, ticker)
  end
  return pf
end
_set_ticker_close!(g::Group{D}, ticker::String) where {D} = begin
  @inbounds for P in g.positions
    P.derivative.underlying.ticker == ticker && request_to_close(P)
  end
end

"""
    has_position(pf::Portfolio, ticker::String)

Return `true` if the portfolio holds any open position (long or short) in `ticker`.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
ticker=B.market.assets[2].ticker;
A=B.market.data[ticker];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
has_position(B.portfolio, ticker)
# output

true
```
"""
function has_position(pf::Portfolio, ticker::String)
  (_has_ticker(pf.buy, ticker) || _has_ticker(pf.sell, ticker)) && return true
  for g in pf.others
    _has_ticker(g, ticker) && return true
  end
  return false
end
_has_ticker(g::Group{D}, ticker::String) where {D} = begin
  @inbounds for P in g.positions
    P.derivative.underlying.ticker == ticker && !is_closed(P) && return true
  end
  return false
end

"""
    position_direction(pf::Portfolio, ticker::String)

Return `:long`, `:short`, or `:flat` for the first open position in `ticker`.

```jldoctest
Random.seed!(1);
B=broker(3,1000);
ticker=B.market.assets[2].ticker;
A=B.market.data[ticker];
O=Order(Buy(A,10));
place_order!(B,O);
Orcus.process_order!(B,O);
position_direction(B.portfolio, ticker)
# output

:long
```
"""
function position_direction(pf::Portfolio, ticker::String)
  d = _ticker_direction(pf.buy, ticker)
  d === :none || return d
  d = _ticker_direction(pf.sell, ticker)
  d === :none || return d
  for g in pf.others
    d = _ticker_direction(g, ticker)
    d === :none || return d
  end
  return :flat
end
# `:none` = no open position for `ticker` in this group (`:flat` is a valid direction, v == 0)
_ticker_direction(g::Group{D}, ticker::String) where {D} = begin
  @inbounds for P in g.positions
    (P.derivative.underlying.ticker == ticker && !is_closed(P)) || continue
    v = value(P)
    return if v > 0
      :long
    elseif v < 0
      :short
    else
      :flat
    end
  end
  return :none
end

# ── cold / introspection: Dict-compatible accessors ───────────────────────────
# Materialized (re-iterable) so callers like `keys(pf)` used twice, or `first(values(pf))`,
# behave like the old Dict. All cold paths (tests, status, pnl rollups, examples).
Base.length(pf::Portfolio) = pf.n
Base.isempty(pf::Portfolio) = pf.n == 0

function Base.values(pf::Portfolio)
  out = Vector{Position}(undef, pf.n)
  i = _append_values!(out, pf.buy, 0)
  i = _append_values!(out, pf.sell, i)
  for g in pf.others
    i = _append_values!(out, g, i)
  end
  return out
end
_append_values!(out, g::Group{D}, i) where {D} = begin
  @inbounds for P in g.positions
    out[i += 1] = P
  end
  i
end

function Base.keys(pf::Portfolio)
  out = Vector{InstrumentKey}(undef, pf.n)
  i = _append_keys!(out, pf.buy, 0)
  i = _append_keys!(out, pf.sell, i)
  for g in pf.others
    i = _append_keys!(out, g, i)
  end
  return out
end
_append_keys!(out, g::Group{D}, i) where {D} = begin
  @inbounds for k in g.keys
    out[i += 1] = k
  end
  i
end

Base.haskey(pf::Portfolio, key::InstrumentKey) =
  _haskey(pf.buy, key) || _haskey(pf.sell, key) || any(g -> _haskey(g, key), pf.others)
_haskey(g::Group{D}, key) where {D} = _find_key(g, key) != 0

function Base.getindex(pf::Portfolio, key::InstrumentKey)
  P = _get(pf.buy, key)
  P === nothing || return P
  P = _get(pf.sell, key)
  P === nothing || return P
  for g in pf.others
    Q = _get(g, key)
    Q === nothing || return Q
  end
  throw(KeyError(key))
end
function _get(g::Group{D}, key) where {D}
  idx = _find_key(g, key)
  idx == 0 ? nothing : @inbounds g.positions[idx]
end
