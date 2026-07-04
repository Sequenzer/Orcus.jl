

export Strategy,
    next,
    init,
    @generate_strategy,
    @strategy_methods

abstract type Strategy end

next(s::Strategy) = error("No next method defined for Strategy \"$(typeof(s))\"")
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
    name = decl isa Expr && decl.head === :(::) ? decl.args[1] :
           decl isa Symbol ? decl :
           error("@generate_strategy: invalid field spec `$(spec)`")
    kw = has_default ? Expr(:kw, name, default) : name
    return (decl=decl, name=name, kw=kw)
end

macro generate_strategy(StrategyName::Symbol, next::Symbol, init::Symbol, fields...)
    isdefined(Main,StrategyName) && error("Symbol \"$(StrategyName)\" is already defined")

    parsed     = map(_strategy_field, fields)
    decls      = [f.decl for f in parsed]                 # extra struct fields
    kws        = [f.kw   for f in parsed]                 # keyword-constructor params
    assigns    = [:(this.$(f.name) = $(f.name)) for f in parsed]

    strct = quote
        mutable struct $StrategyName <: Strategy
            broker::Broker
            market::Market
            $(decls...)
            function $StrategyName(broker::Broker; $(kws...))
                this = new()
                this.broker = broker
                this.market = broker.market
                $(assigns...)
                return this
            end
        end
    end
    functs = quote
        function next(s::$StrategyName)
            Main.$next(s)
        end
        function init(s::$StrategyName)
            Main.$init(s)
        end
    end
    eval(quote
        export $StrategyName
        $strct
        $functs
    end)
    return nothing
end

permutations(x::Vector{Int}) = [x[perm] for perm in permutations(1:length(x))]

# For complex strategies with custom fields: user defines the struct manually
# (must include broker::Broker and market::Market), then calls this macro to
# register next/init dispatch.
#
# Usage:
#   mutable struct MyStrat <: Strategy
#       broker::Broker
#       market::Market
#       my_field::SomeType
#       MyStrat(b::Broker) = new(b, b.market, initial_value)
#   end
#   @strategy_methods MyStrat my_next_fn my_init_fn
macro strategy_methods(StrategyName::Symbol, next_fn::Symbol, init_fn::Symbol)
    eval(quote
        function next(s::Main.$StrategyName)
            Main.$next_fn(s)
        end
        function init(s::Main.$StrategyName)
            Main.$init_fn(s)
        end
    end)
    return nothing
end

#=

tmp_next(s::Strategy) = println("next")
tmp_init(s::Strategy) = println("init")


@generate_strategy TestStrategy tmp_next tmp_init
s = TestStrategy(Broker(Market(),1000))
init(s)


=#
