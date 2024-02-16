#Tests for Utils.jl

@testset "Utilities" begin
    asset = AssetData(missing)
    date = Date(2019,1,1)
    @test ismissing(asset[date])
end

