@testset verbose=false "Position" begin 
@testset verbose=false "core" begin
    @testset "core.functions" begin
        Random.seed!(1234);
        A = asset()
        B = Buy(A, 10)
        O = Order(B, 100)
        T = Trade(O)
        P = Position(T)
        @test P.closed == false
        @test P.requestToClose == false
        @test volume(P) == 100
        @test price(P.derivative)-value(P.derivative) == 10
        requestToClose(P)
        @test P.requestToClose == true
        Orcus.close(P)
        @test P.closed == true
        
    end
end
end
