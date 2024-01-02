
export 
    Broker,
    placeOrder!,
    processOrder!,
    processLastOrder!,
    processOrders!,
    resolvePortfolio!,
    processAll!,
    requestToCloseAll!,
    cashHistory,
    toIndex,
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
    function Broker(market::Market,cash::Real)
        this = new()
        this.cash = cash
        this.market = market
        this.portfolio = Vector{Position}()
        this.orders = Vector{Order}()
        this.history = Vector{Trade}()
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
    today = end_date(B)
    check_books && (O in B.orders  || error("Order not in Orderbook"))
    isfulfilled(O) && error("Order already fulfilled")
    B.cash - price(O) >= 0 || error("Insufficient funds")
    B.cash -= fulfill(O,today)
    ##Find & Delte Order in Orderbook
    i = findfirst(x -> x== O,B.orders)
    deleteat!(B.orders,i)

    ##Add Trade to History
    T = Trade(O,today)
    push!(B.history,T)
    ##Add Position to Portfolio
    P = Position(T)
    push!(B.portfolio,P)

    return B;
end

function processLastOrder!(B::Broker)
    today = end_date(B)
    isempty(B.orders) && error("No Orders to process")
    order = last(B.orders)
    B.cash - price(order) >= 0 || error("Insufficient funds")
    B.cash -= fulfill(order,today)
    pop!(B.orders)

    ##Add Trade to History
    T = Trade(order,today)
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
            T = close(P, end_date(B)) 
            val = -value(T) #Negative because we are closing the position
            T.delta_cash = val
            if B.cash + val >= 0
                B.cash += val
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
    today = end_date(B)
    isempty(B.orders) && return
    order = last(B.orders)
    B.cash - price(order) >= 0 || return
    B.cash -= fulfill(order,today)
    pop!(B.orders)

    ##Add Trade to History
    T = Trade(order,today)
    T.delta_cash = -price(order)
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
    Date: $(end_date(B))
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

    
function end_date(B::Broker)
    return end_date(B.market)
end



function cashHistory(B::Broker)
    cash_vector = Tuple{DateTime, Real}[(end_date(B),B.cash)]
    cash = B.cash
    for t in reverse(B.history)
        cash -= t.delta_cash
        push!(cash_vector,(t.date,cash))
    end
    cash_vector = reverse(cash_vector) 
    return cash_vector
end



"""

    toIndex(B::Broker)::Asset

Convert a Broker to an Asset

```jldoctest
Random.seed!(1234);
x=Asset();
y=Asset();
M=Market([x,y]);
B = Broker(M,1000);
BT = Backtest(M,CrossOverStrategy,1000)
runTest(BT)
A = toIndex(BT.broker)
```

"""


function toIndex(B::Broker)::Asset
    A = Asset("Broker")
    A.data = Dict{String,AssetData}()
    A.data["Cash"] = AssetData(missing)
    for (date,cash) in cashHistory(B)
        A.data["Cash"][date] = cash
    end

    return A
end

function plot(B::Broker)
    plot(toIndex(B),"Cash")
end







