
using Test
using Qt

@testset "Qt.jl" begin
    @testset "Asset" begin 
        @test isa(Qt.Asset("Test"),Main.Qt.Asset)
        @test isa(Asset("Test"),Asset) 
        @test isa(Asset(),Asset)
        @test length(Asset().data["Open"])==731   
    end
end
