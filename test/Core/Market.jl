@testset verbose=false "Market" begin 
@testset verbose=false "core" begin
    @testset "core.functions" begin
        Random.seed!(1234);
        M=market(3);
        @test length(M)==3651
        @test height(M)==3
        @test height(market([asset(),asset()]))==2
        @test size(M)==(3,3651) 
    end
    @testset "addAsset!" begin
        Random.seed!(1234);
        M=market(3);
        addAsset!(M,asset())
        @test length(M)==3651
        @test height(M)==4
    end
end
end
