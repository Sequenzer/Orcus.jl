@testset verbose=false "Market" begin
  @testset verbose=false "core" begin
    @testset "core.functions" begin
      Random.seed!(1234);
      M=market(3);
      @test length(M)==3651
      @test height(M)==3
      @test height(market([asset(), asset()]))==2
      @test size(M)==(3, 3651)
    end
    @testset "add_asset!" begin
      Random.seed!(1234);
      M=market(3);
      add_asset!(M, asset())
      @test length(M)==3651
      @test height(M)==4
    end
  end
  @testset "axis" begin
    A = Asset("T1", [1.0 2.0 3.0 4.0; 5.0 6.0 7.0 8.0], ["Open", "Close"])
    M = market([A])
    @test !has_axis(M)
    @test_throws Exception timestamp(M, 1)
    @test_throws Exception bar_of(M, DateTime(2020))

    ax = DateTime.(Date(2020, 1, 1):Day(1):Date(2020, 1, 4))
    @test_throws AssertionError set_axis!(M, ax[1:3])
    @test_throws AssertionError set_axis!(M, reverse(ax))
    set_axis!(M, ax)
    @test has_axis(M)
    @test timestamp(M, 2) == DateTime(2020, 1, 2)
    @test bar_of(M, DateTime(2020, 1, 3)) == 3
    @test bar_of(M, DateTime(2020, 1, 3, 12)) == 3
    @test bar_of(M, DateTime(2019, 12, 31)) == 0
    @test bar_of(M, Date(2020, 1, 4)) == 4

    M2 = market([copy(A)])
    set_axis!(M2, collect(Date(2020, 1, 1):Day(1):Date(2020, 1, 4)))
    @test timestamp(M2, 1) == DateTime(2020, 1, 1)

    C = copy(M)
    @test C.axis == ax
    @test C.axis !== M.axis
    S = M[2:3]
    @test S.axis == ax[2:3]
    Tr = trim_to_length(M, 2)
    @test Tr.axis == ax[3:4]
    Msh = copy(M)
    shorten!(Msh, 1:2)
    @test Msh.axis == ax[1:2]
  end
end
