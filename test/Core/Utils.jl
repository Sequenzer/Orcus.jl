#Tests for Utils.jl

@testset "Utilities" begin
    asset = AssetData(missing)
    date = Date(2019,1,1)
    @test ismissing(asset[date])

    @testset "DataSeries" begin
        dp1 = Float64[1,2,NaN,4,5]
        dp2 = Float64[1,2,NaN,4,NaN,NaN]
        ds = data_series([dp1, fill(NaN,6), dp2])

        @test ds[1,1] == 1
        @test isnan(ds[1,3])
        @test size(ds) == (3,6)

        ds2 = data_series([dp1,dp2])
        @test size(ds2) == (2,6)
        



    end


end

