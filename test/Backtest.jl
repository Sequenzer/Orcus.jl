

@testset verbose=true "Backtest" begin

    #Define single buy strategy
    global tst_init(_::Strategy) = nothing
    global function tst_next(s::Strategy)
        #only buy at the start every asset
        length(s.broker.portfolio) > 0 && return
        O = Order(Buy(s.market["TSTS"],10))
        placeOrder!(s.broker,O) 
    end   
    @generateStrategy SBuyStrategy tst_next tst_init



    @testset "constant" begin
        ticker = "TSTS" 
        i = Date(2010):Dates.Day(5):Date(2011)
        prp_func = (x)->0
        A = Asset(ticker;interval=i,prop_func=prp_func)
        M = Market([A])

        T = Backtest(M, SBuyStrategy, 1000)
        runTest(T)

        P = T.broker.portfolio[1]

        @test value(P)==100
        @test price(P)==110
    end

    @testset "linear+" begin
        ticker = "TSTS" 
        i = Date(2010):Dates.Day(5):Date(2012)
        prp_func = (x)->1
        A = Asset(ticker;interval=i,prop_func=prp_func)

        @test reduce(max,values(A["Close"]))==1423
        @test minimum_value(A)==100

        timeline = collect(keys(A2["Open"]))
        @test timeline[1]==Date(2010,1,1)
        @test timeline[end]==Date(2019,12,30)

        @test A2["Open"][timeline[end]] == 6670

    end
    @testset "linear-" begin
        ticker = "TSTS" 
        i1 = Date(2010):Dates.Day(5):Date(2020)
        prp_func1 = (x)->-1
        A2 = Asset(ticker;interval=i1,prop_func=prp_func1)

        @test reduce(max,values(A2["Open"]))==100
        @test reduce(min,values(A2["Open"]))==-6470

        timeline = collect(keys(A2["Open"]))
        @test timeline[1]==Date(2010,1,1)
        @test timeline[end]==Date(2019,12,30)

        @test A2["Open"][timeline[end]] == -6470

    end
end

