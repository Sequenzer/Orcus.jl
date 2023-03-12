

using Qt:Qt

@testset "Qt.jl" begin
    # Write your tests here.
    @test isa(Qt.Asset("Test"),Main.Qt.Asset)
end
