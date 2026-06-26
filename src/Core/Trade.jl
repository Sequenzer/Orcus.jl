#Trade

export 
    Trade


"""
    
    Trade(O::Order)


```jldoctest
Random.seed!(1234);
A = asset();
B = Buy(A, 10);
O = order(B, 100);
T = Trade(O);
value(T)

# output

11021.778063564074

```
"""
mutable struct Trade
    derivative::Derivative
    volume::Float64
    date::Int
    delta_cash::Float64
    function Trade(O::Order, date::Int=length(O.derivative.underlying))
        self = new()
        self.derivative = O.derivative
        self.volume = Float64(O.volume)
        self.date = date
        self.delta_cash = 0.0   # set by the broker at fill time
        return self
    end
    function Trade()
        self = new()
        self.delta_cash = 0.0
        return self
    end
end


Base.show(io::IO, T::Trade) = print(io, "A $(T.derivative.underlying.ticker) trade of $(T.volume) $(name(T.derivative)) on $(T.date)")

value(T::Trade) = T.volume * value(T.derivative)
price(T::Trade) = T.volume * price(T.derivative)
