

export Strategy,
    next,
    init,
    @generateStrategy



abstract type Strategy end

next(s::Strategy) = error("No next method defined for Strategy \"$(typeof(s))\"")
init(s::Strategy) = error("No init method defined for Strategy \"$(typeof(s))\"")


macro generateStrategy(StrategyName::Symbol, next::Symbol, init::Symbol)
    isdefined(Main,StrategyName) && error("Symbol \"$(StrategyName)\" is already defined")
    #isdefined(Main,next) || error("Symbol \"$(next)\" is not defined")
    #isdefined(Main,init) || error("Symbol \"$(init)\" is not defined")


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
    return eval(quote
        export $StrategyName
        
        $strct
        $functs
    end)
end

#=

tmp_next(s::Strategy) = println("next")
tmp_init(s::Strategy) = println("init")


@generateStrategy TestStrategy tmp_next tmp_init
s = TestStrategy(Broker(Market(),1000))
init(s)


=#
