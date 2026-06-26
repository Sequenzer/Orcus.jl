

export Strategy,
    next,
    init,
    @generateStrategy,
    @strategyMethods

abstract type Strategy end

next(s::Strategy) = error("No next method defined for Strategy \"$(typeof(s))\"")
init(s::Strategy) = error("No init method defined for Strategy \"$(typeof(s))\"")


macro generateStrategy(StrategyName::Symbol, next::Symbol, init::Symbol)
    isdefined(Main,StrategyName) && error("Symbol \"$(StrategyName)\" is already defined")

    strct = quote
        mutable struct $StrategyName <: Strategy
            broker::Broker
            market::Market
            function $StrategyName(broker::Broker)
                this = new()
                this.broker = broker
                this.market = broker.market
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
#   @strategyMethods MyStrat my_next_fn my_init_fn
macro strategyMethods(StrategyName::Symbol, next_fn::Symbol, init_fn::Symbol)
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


@generateStrategy TestStrategy tmp_next tmp_init
s = TestStrategy(Broker(Market(),1000))
init(s)


=#
