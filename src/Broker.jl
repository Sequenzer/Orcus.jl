
export 
    Broker,
    placeOrder!,
    processOrder!,
    processLastOrder!,
    processOrders!,
    resolvePortfolio!,
    processAll!,
    requestToCloseAll!,
    status




"""

    Market(cash::Real,market::Market)

The Order executing Unit in the System.


```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
B = Broker(M,1000);
isa(B,Broker)
# output

true
```
"""
mutable struct Broker
    cash::Real
    market::Market
    portfolio::Vector{Position}
    orders::Vector{Order}
    history::Vector{Trade}
    date::DateTime
    function Broker(market::Market,cash::Real)
        this = new()
        this.cash = cash
        this.market = market
        this.portfolio = Vector{Position}()
        this.orders = Vector{Order}()
        this.history = Vector{Trade}()
        this.date = Dates.DateTime(2020,1,1)
        return this
    end
end

function Broker(n_Assets::Int,cash::Real)
    M=Market(Asset[]);
    foreach(x->addAsset!(M,Asset()),1:n_Assets)
    return Broker(M,cash)
end

Base.show(io::IO,B::Broker) = print(io,"Broker with $(round(B.cash;digits=2)) funds and $(length(B.orders)) open orders")


"""

    placeOrder!(B::Broker,O::Order)

Place an Order in the Broker's Orderbook

```jldoctest
Random.seed!(1234);
B = Broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
B
```
"""
function placeOrder!(B::Broker,O::Order)
     #ToDo Check if requirements for placement are met
    push!(B.orders,O)
    return;
end


"""

    processOrder!(B::Broker,O::Order,check_books::Bool=true)

Process an Order in the Broker's Orderbook

```jldoctest
Random.seed!(1234);
B = Broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
processOrder!(B,O)
B.history
B.portfolio
```

"""
function processOrder!(B::Broker,O::Order,check_books::Bool=true)
    check_books && (O in B.orders  || error("Order not in Orderbook"))
    isfulfilled(O) && error("Order already fulfilled")
    B.cash - price(O) >= 0 || error("Insufficient funds")
    B.cash -= fulfill(O,B.date)
    ##Find & Delte Order in Orderbook
    i = findfirst(x -> x== O,B.orders)
    deleteat!(B.orders,i)

    ##Add Trade to History
    T = Trade(O,B.date)
    push!(B.history,T)
    ##Add Position to Portfolio
    P = Position(T)
    push!(B.portfolio,P)

    return B;
end

function processLastOrder!(B::Broker)
    isempty(B.orders) && error("No Orders to process")
    order = last(B.orders)
    B.cash - price(order) >= 0 || error("Insufficient funds")
    B.cash -= fulfill(order,B.date)
    pop!(B.orders)

    ##Add Trade to History
    T = Trade(order,B.date)
    push!(B.history,T)
    ##Add Position to Portfolio
    P = Position(T)
    push!(B.portfolio,P)

    return B;
end

"""

    resolvePortfolio!(B::Broker)

Resolve the Portfolio of the Broker, i.e. close all positions that have a requestToClose flag set to true.

```jldoctest
Random.seed!(1234);
B = Broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Sell(A,10))
placeOrder!(B,O)
processOrder!(B,O)
requestToClose(B.portfolio[1])
resolvePortfolio!(B)
```

"""
function resolvePortfolio!(B::Broker)
    for P in B.portfolio
        if P.requestToClose
            T = close(P) 
            price = -value(T) #Negative because we are closing the position

            if B.cash + price >= 0
                B.cash += price
                push!(B.history,T)
            else
                P.closed = false 
                println("Not enough funds to close position")
                return
            end

        end
    end
    B.portfolio = filter(x->!x.closed,B.portfolio)
    return B
end



"""

    processOrder!(B::Broker,O::Order,check_books::Bool=true)

Process an Order in the Broker's Orderbook

```jldoctest
Random.seed!(1234);
B = Broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
processOrders!(B)
B.history
```

"""
function processOrders!(B::Broker)
    isempty(B.orders) && return
    order = last(B.orders)
    B.cash - price(order) >= 0 || return
    B.cash -= fulfill(order,B.date)
    pop!(B.orders)

    ##Add Trade to History
    T = Trade(order,B.date)
    push!(B.history,T)
    ##Add Position to Portfolio
    P = Position(T)
    push!(B.portfolio,P)

    processOrders!(B)
    return B;
end

function processAll!(B::Broker)
    processOrders!(B)
    resolvePortfolio!(B)
    return B
end




"""

    status(B::Broker,digits::Int=2)

Print the status of the Broker

```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
B = Broker(M,1000);
status(B)

# output

========================================
Date: 2020-01-01T00:00:00
Cash: 1000.0
Number of orders: 0
Number of positions: 0
Number of trades: 0
========================================
```
"""
function status(B::Broker,digits::Int=2)
    otp ="="^40*"\n"*"""
    Date: $(B.date)
    Cash: $(round(B.cash;digits=digits))
    Number of orders: $(length(B.orders))
    Number of positions: $(length(B.portfolio))
    Number of trades: $(length(B.history))
    """*"="^40
    print(otp)
    return
end





function requestToCloseAll!(B::Broker)
    for P in B.portfolio
        requestToClose(P)
    end
    return
end

