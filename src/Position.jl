#Positio 

export 
    Position,
    volume,
    value,
    uValue,
    requestToClose 



"""
```julia
A = Asset()
B = Buy(A, 10)
O = Order(B, 100)
T = Trade(O)
P = Position(T)
```

"""
mutable struct Position
    derivative::Derivative
    trade::Trade  
    closed::Bool  
    requestToClose::Bool
    function Position(T::Trade)
        self = new()    
        self.derivative = T.derivative
        self.trade = T
        self.closed = false
        self.requestToClose = false
        return self
    end
end

Base.show(io::IO, P::Position) = P.closed ? 
print(io, "A closed position of $(volume(P)) $(P.derivative.name) on $(P.derivative.underlying.ticker)") : 
    print(io, "A open position of $(volume(P)) $(P.derivative.name) on $(P.derivative.underlying.ticker)")



volume(P::Position) = P.trade.volume
value(P::Position) = P.trade.volume * value(P.derivative)
uValue(P::Position) = P.trade.volume * uValue(P.derivative)
price(P::Position) = P.trade.volume * P.derivative.price
absReturn(P::Position) = P.trade.volume * absReturn(P.derivative)
pctReturn(P::Position) = pctReturn(P.derivative)
logReturn(P::Position) = value(P)<=0 ? -Inf : log(value(P)/price(P))


"""
    plot(P::<Position)

Plot the payoutstructure of the underlying derivative.


```

"""
function plot(P::Position)
    plot(P.derivative)
end

"""

    Trade(P::Position)

A trade that is the result of closing a position.

```julia
A = Asset()
B = Buy(A, 10)
O = Order(B, 100)
T = Trade(O)
cT=Trade(P)
value(cT)
```

"""
function Trade(P::Position)
    self = Trade()
    self.derivative = P.derivative
    self.volume = -P.trade.volume
    return self
end

function requestToClose(P::Position)
    P.requestToClose = true
    return P
end

function close(P::Position)
    T = Trade(P)
    P.closed = true
    return T
end



