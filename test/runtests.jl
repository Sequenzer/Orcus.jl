using Qt
using Test


@testset "Qt.jl" begin
    # Write your tests here.
    @test Qt.test_function()=="hello there"
end
