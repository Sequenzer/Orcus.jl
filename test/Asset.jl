#Test for Asset.jl


@testset verbose=true "Asset" begin 
@testset verbose=true "basic" begin


    x=Asset("AAPL")
    @test isequal(x.ticker,"AAPL")
    @test isa(x,Main.Qt.Asset)

    @test isa(Asset("TSTS"),Asset) 

    y = Asset()
    @test isa(y,Asset)
    @test length(y.data["Open"])==731   


    @testset "constant" begin
        ticker = "TSTS" 
        i1 = Date(2010):Dates.Day(5):Date(2020)
        prp_func1 = (x)->0
        A2 = Asset(ticker;interval=i1,prop_func=prp_func1)

        @test reduce(max,values(A2["Open"]))==100
        @test reduce(min,values(A2["Open"]))==100
    end

    @testset "linear+" begin
        ticker = "TSTS" 
        i1 = Date(2010):Dates.Day(5):Date(2020)
        prp_func1 = (x)->1
        A2 = Asset(ticker;interval=i1,prop_func=prp_func1)

        @test reduce(max,values(A2["Open"]))==6670
        @test reduce(min,values(A2["Open"]))==100

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





@testset "Indicator" verbose=true begin
    x = Asset()
    SMA10=IndicatorGenerator(simple_average,10)

    @testset "IndicatorGenerator" begin
        @test SMA10.window == 10
    end 
    @testset "calculateIndicator" begin
        @test length(calculateIndicator(SMA10,x,"Close"))==731
    end


end

end


