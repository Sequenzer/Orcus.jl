@testset verbose=false "Asset" begin 
@testset verbose=false "core" begin
    @testset "constructor" begin
        dp1 = Float64[1,2,NaN,4,5]
        dp2 = Float64[1,2,NaN,4,NaN,NaN]
        ds = data_series([dp1, fill(NaN,6), dp2])

        @test isa(asset("AAPL",ds,["1","2","3"]),Asset)
    end
    @testset "constant" begin
        ticker = "TSTS" 
        i = 1:1:100
        prp_func = (x)->0
        A = asset(ticker,i,prp_func,100,10)
        @test A["Close"] == fill(100,100)
        @test length(A) == 100
    end
    @testset "linear+" begin
        ticker = "TSTS" 
        i = 1:1:100
        prp_func = (x)->1
        A = asset(ticker,i,prp_func,100,2)
        @test A["Close"] == 100 .+ i
        @test A["High"][1] == 101
        @test A["Low"][1] == 100
        @test A["Low"][end] == 199
        @test length(A) == 100
        @test value(A) == A["Close"][end]
        @test value(A) == 200
        @test value(A,"Low") == 199
    end
    @testset "linear-" begin
        ticker = "TSTS" 
        i = 1:1:100
        prp_func = (x)->-1
        A = asset(ticker,i,prp_func,100,2)
        @test A["Close"] == 100 .- i
        @test A["High"][1] == 100
        @test A["Low"][1] == 99
        @test A["Low"][end] == 0
        @test length(A) == 100
    end

    @testset "add_datapoint!" begin
        ticker = "TSTS" 
        i = 1:1:100
        prp_func = (x)->0
        A = asset(ticker,i,prp_func,100,2)
        SMA20=IndicatorGenerator(simple_average,20)
        apply_indicator(SMA20,A,"Close","SMA20")
        add_datapoint!(A,Float64[113,113,113,113,NaN])
        add_datapoint!(A,Float64[113,113,113,113,NaN])
        @test A.data[5,end] == 100.65
        @test A.data[4,end] == 113
    end
end
end

