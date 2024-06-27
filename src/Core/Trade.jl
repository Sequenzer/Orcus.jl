#Trade

export 
    Trade


"""
    
    Trade(O::Order)


```jldoctest
Random.seed!(1234);
A = asset();
B = Buy(A, 10);
O = Order(B, 100);
T = Trade(O);
value(T)

# output

11021.778063564074

```
"""
mutable struct Trade
    derivative::Derivative
    volume::Real
    date::Int
    delta_cash::Real
    function Trade(O::Order, date::Int=length(O.derivative.underlying))
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


Base.show(io::IO, T::Trade) = print(io, "A $(T.derivative.underlying.ticker) trade of $(T.volume) $(name(T.derivative)) on $(T.date)")

value(T::Trade) = T.volume * value(T.derivative)
price(T::Trade) = T.volume * T.derivative.price
