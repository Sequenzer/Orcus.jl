
"""
    Strategy

Abstract type for strategies. A concrete strategy pairs a `next`/`init` method (wired via
[`@generate_strategy`](@ref) or [`@strategy_methods`](@ref)) with the fields it needs.
"""
abstract type Strategy end

"""
    next(s::Strategy)

Called once per bar; the strategy's per-bar logic. Errors unless wired via
[`@generate_strategy`](@ref)/[`@strategy_methods`](@ref).

```jldoctest
struct Dummy <: Strategy end
try
    next(Dummy())
catch e
    println(sprint(showerror, e))
end
# output

No next method defined for Strategy "Dummy"
```
"""
next(s::Strategy) = error("No next method defined for Strategy \"$(typeof(s))\"")

"""
    init(s::Strategy)

Called once before the backtest loop starts; typically attaches indicators. Errors unless
wired via [`@generate_strategy`](@ref)/[`@strategy_methods`](@ref).

```jldoctest
struct Dummy <: Strategy end
try
    init(Dummy())
catch e
    println(sprint(showerror, e))
end
# output

No init method defined for Strategy "Dummy"
```
"""
init(s::Strategy) = error("No init method defined for Strategy \"$(typeof(s))\"")

# Parse a trailing field spec passed to @generate_strategy. Accepts `name::Type`,
# `name::Type = default`, `name` (untyped), or `name = default`. Returns the field
# declaration (for the struct body), the field name, and the keyword-arg expression
# (`Expr(:kw, name, default)` when a default is given, bare `name` for a required kwarg).
function _strategy_field(spec)
  if spec isa Expr && spec.head === :(=)
    decl, default, has_default = spec.args[1], spec.args[2], true
  else
    decl, default, has_default = spec, nothing, false
  end
  name = if decl isa Expr && decl.head === :(::)
    decl.args[1]
  elseif decl isa Symbol
    decl
  else
    error("@generate_strategy: invalid field spec `$(spec)`")
  end
  kw = has_default ? Expr(:kw, name, default) : name
  return (decl=decl, name=name, kw=kw)
end

"""
    @generate_strategy StrategyName next_fn init_fn field...

Generate a `Strategy` subtype named `StrategyName`, wired to call `next_fn`/`init_fn` for its
`next`/`init` methods. Each trailing `field` is `name`, `name::Type`, `name = default`, or
`name::Type = default` — swept parameters for [`batch_backtest`](@ref) should be typed. Like
[`@strategy_methods`](@ref), must be invoked where `next_fn`/`init_fn` resolve in `Main` — a
top-level script or REPL session, not from inside a package, module, or test.

```jldoctest
tmp_next(s) = nothing;
tmp_init(s) = nothing;
@generate_strategy TestStrategy tmp_next tmp_init;
s = TestStrategy(Broker(Market(),1000));
s isa Strategy
# output

true
```
"""
macro generate_strategy(StrategyName::Symbol, next::Symbol, init::Symbol, fields...)
  if isdefined(Main, StrategyName)
    existing = getproperty(Main, StrategyName)
    existing isa Type && existing <: Strategy ||
      error("Symbol \"$(StrategyName)\" is already defined and is not an Orcus Strategy")
  end

  parsed = map(_strategy_field, fields)
  decls = [f.decl for f in parsed]                 # extra struct fields
  kws = [f.kw for f in parsed]                 # keyword-constructor params
  assigns = [:(this.$(f.name) = $(f.name)) for f in parsed]

  # Redefining a struct in place is not supported by Julia (errors on differing
  # fields); instead generate a fresh internal type each call and rebind the
  # public name to it via a plain global, which Julia allows to be reassigned.
  InternalName = Symbol(StrategyName, :_, _unique_type_suffix())

  strct = quote
    mutable struct $InternalName <: Strategy
      broker::Broker
      market::Market
      $(decls...)
      function $InternalName(broker::Broker; $(kws...))
        this = new()
        this.broker = broker
        this.market = broker.market
        $(assigns...)
        return this
      end
    end
  end
  functs = quote
    function next(s::$InternalName)
      Main.$next(s)
    end
    function init(s::$InternalName)
      Main.$init(s)
    end
  end
  eval(
    quote
      $strct
      $functs
      Base.nameof(::Type{$InternalName}) = $(QuoteNode(StrategyName))
      Base.show(io::IO, ::Type{$InternalName}) = print(io, $(QuoteNode(StrategyName)))
      global $StrategyName = $InternalName
      export $StrategyName
    end,
  )
  return nothing
end

permutations(x::Vector{Int}) = [x[perm] for perm in permutations(1:length(x))]

"""
    @strategy_methods StrategyName next_fn init_fn

Wire `next`/`init` dispatch for a manually-defined `Strategy` subtype (one with custom fields
beyond `broker`/`market`), calling `next_fn`/`init_fn`. Use [`@generate_strategy`](@ref) instead
when a generated struct is enough. Like `@generate_strategy`, must be invoked where
`StrategyName` resolves in `Main` — a top-level script or REPL session, not from inside a
package, module, or test.

```julia
mutable struct MyStrat <: Strategy
    broker::Broker
    market::Market
    MyStrat(b::Broker) = new(b, b.market)
end
@strategy_methods MyStrat my_next my_init
s = MyStrat(Broker(Market(), 1000))
```
"""
macro strategy_methods(StrategyName::Symbol, next_fn::Symbol, init_fn::Symbol)
  eval(
    quote
      function next(s::Main.$StrategyName)
        Main.$next_fn(s)
      end
      function init(s::Main.$StrategyName)
        Main.$init_fn(s)
      end
    end,
  )
  return nothing
end
