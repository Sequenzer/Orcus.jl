#Trade

export 
    Trade


"""
    
    Trade(O::Order)


```julia
A = Asset()
B = Buy(A, 10)
O = Order(B, 100)
T = Trade(O)

```

"""
mutable struct Trade
    derivative::Derivative
    volume::Real
    date::DateTime
    function Trade(O::Order, date::DateTime=now())
        self = new()
        self.derivative = O.derivative
        self.volume = O.volume
        self.date = date 
        return self
    end
    function Trade()
        return new()
    end
end


Base.show(io::IO, T::Trade) = print(io, "A trade of $(T.volume) $(T.derivative.name) on $(T.date)")

value(T::Trade) = T.volume * value(T.derivative)

