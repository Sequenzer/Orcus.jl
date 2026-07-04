# Portfolio — type-grouped position storage.
#
# Positions are segregated by concrete derivative type into homogeneously-typed `Group{D}`s.
# Two reasons:
#   1. No boxing — iterating a `Group{D}` yields concrete `Position{D}`, so `value(P)` infers
#      `Float64` and the per-bar equity mark is allocation-free regardless of universe size.
#   2. No per-bar hashing — within a group, the live positions live in a contiguous
#      `Vector{Position{D}}` (cache-friendly, branch-predictable iteration); a `Dict` index map
#      is kept only for the *per-order* key lookup, which is sparse relative to the bar loop.
# Every hot accessor is a **function barrier**: one dispatch per type-group (union-split away
# for the built-in Buy/Sell), after which the inner loop is fully concrete.

export Portfolio,
  total_value,
  get_or_create!

"""
    Group{D}

Live positions for one concrete derivative type `D`. `positions` and `keys` are parallel
contiguous vectors (hot-path iteration); `index` maps an `InstrumentKey` to its slot for O(1)
per-order lookup. Removal is swap-pop: the last slot is moved into the freed slot and its
index entry patched.
"""
struct Group{D<:Derivative}
  positions::Vector{Position{D}}
  keys::Vector{InstrumentKey}
  index::Dict{InstrumentKey,Int}
end
Group{D}() where {D<:Derivative} =
  Group{D}(Position{D}[], InstrumentKey[], Dict{InstrumentKey,Int}())

"""
    Portfolio

Netted positions grouped by concrete derivative type. `groups` is a `Vector` of `Group{D}`
objects (one per distinct derivative type — typically 1–2), held behind `Any` so the container
is open to user-defined derivative types. A bare Vector, not a Dict: per-bar iteration is a
direct 1–2 element walk (no hash-slot scan), and per-order type lookup is a short linear scan
that beats hashing a `DataType`. `n` caches the total open-position count for O(1) `length`;
`_acc` is a reused scratch accumulator so the per-group barrier returns `nothing` (no boxed
return).
"""
mutable struct Portfolio
  groups::Vector{Any}          # Group{D} objects, one per concrete derivative type
  n::Int
  _acc::Float64
end

Portfolio() = Portfolio(Any[], 0, 0.0)

# ── hot path: equity mark ─────────────────────────────────────────────────────
"""
    total_value(pf::Portfolio) -> Float64

Sum of `value(P)` over all open positions. The per-group barrier writes into `_acc` and
returns `nothing` (no boxed return); the inner loop is a contiguous, allocation-free scan.
"""
function total_value(pf::Portfolio)
  s = 0.0
  for g in pf.groups                # g::Any — direct Vector walk
    # Union-split the built-in linear types: the `isa` branches are statically typed, so
    # `_group_sum` is specialized, inlined, and returns `Float64` directly (no boxed
    # return) — covering the overwhelmingly common Buy/Sell case. Open-world types take the
    # `else` branch, which routes through the `_acc` scratch field to dodge the boxed return
    # of the one runtime dispatch.
    if g isa Group{Buy}
      s += _group_sum(g)
    elseif g isa Group{Sell}
      s += _group_sum(g)
    else
      pf._acc = 0.0
      _add_group_value!(pf, g)
      s += pf._acc
    end
  end
  return s
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

# ── per-order: locate/create the typed group and position ─────────────────────
@inline function _group!(pf::Portfolio, ::Type{D}) where {D<:Derivative}
  for g in pf.groups
    g isa Group{D} && return g       # `isa` narrows g → type-stable return
  end
  g = Group{D}()
  push!(pf.groups, g)
  return g
end

"""
    get_or_create!(pf, key, der::D) -> Position{D}

Return the live `Position{D}` for `key`, creating an empty one on first fill. Type-stable in
`D` (caller passes a concrete derivative), so the returned position is concrete.
"""
function get_or_create!(pf::Portfolio, key::InstrumentKey, der::D) where {D<:Derivative}
  g = _group!(pf, D)
  idx = get(g.index, key, 0)
  idx != 0 && return @inbounds g.positions[idx]
  P = Position(der)
  push!(g.positions, P)
  push!(g.keys, key)
  g.index[key] = length(g.positions)
  pf.n += 1
  return P
end

# Swap-pop a key out of its (typed) group; returns true if it was present.
function _drop_key!(pf::Portfolio, g::Group{D}, key::InstrumentKey) where {D}
  idx = get(g.index, key, 0)
  idx == 0 && return false
  last_i = length(g.positions)
  if idx != last_i
    @inbounds moved_key = g.keys[last_i]
    @inbounds g.positions[idx] = g.positions[last_i]
    @inbounds g.keys[idx] = moved_key
    g.index[moved_key] = idx
  end
  pop!(g.positions)
  pop!(g.keys)
  delete!(g.index, key)
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
  for g in pf.groups
    _del_from_group!(pf, g, key) && return pf
  end
  return pf
end
_del_from_group!(pf::Portfolio, g::Group{D}, key) where {D} = _drop_key!(pf, g, key)

# ── per-bar scan: positions flagged for close ─────────────────────────────────
"""
    collect_flagged!(buf, pf) -> buf

Fill `buf` with the keys of positions whose `requestToClose` flag is set. One dispatch per
type-group; the inner scan is a contiguous, allocation-free walk of parallel vectors.
"""
function collect_flagged!(buf::Vector{InstrumentKey}, pf::Portfolio)
  empty!(buf)
  for g in pf.groups
    _collect_flagged!(buf, g)
  end
  return buf
end
_collect_flagged!(buf, g::Group{D}) where {D} = begin
  @inbounds for i in eachindex(g.positions)
    g.positions[i].requestToClose && push!(buf, g.keys[i])
  end
end

"""
    set_all_close!(pf)

Flag every open position for close. Barrier per type-group.
"""
function set_all_close!(pf::Portfolio)
  for g in pf.groups
    _set_all_close!(g)
  end
  return pf
end
_set_all_close!(g::Group{D}) where {D} = begin
  @inbounds for P in g.positions
    P.requestToClose = true
  end
end

# ── cold / introspection: Dict-compatible accessors ───────────────────────────
# Materialized (re-iterable) so callers like `keys(pf)` used twice, or `first(values(pf))`,
# behave like the old Dict. All cold paths (tests, status, pnl rollups, examples).
Base.length(pf::Portfolio) = pf.n
Base.isempty(pf::Portfolio) = pf.n == 0

function Base.values(pf::Portfolio)
  out = Vector{Position}(undef, pf.n)
  i = 0
  for g in pf.groups
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
  i = 0
  for g in pf.groups
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

Base.haskey(pf::Portfolio, key::InstrumentKey) = any(g -> _haskey(g, key), pf.groups)
_haskey(g::Group{D}, key) where {D} = haskey(g.index, key)

function Base.getindex(pf::Portfolio, key::InstrumentKey)
  for g in pf.groups
    P = _get(g, key)
    P === nothing || return P
  end
  throw(KeyError(key))
end
function _get(g::Group{D}, key) where {D}
  idx = get(g.index, key, 0)
  idx == 0 ? nothing : @inbounds g.positions[idx]
end
