
export 
    Broker,
    broker,
    placeOrder!,
    processOrder!,
    processLastOrder!,
    processOrders!,
    resolvePortfolio!,
    processAll!,
    requestToCloseAll!,
    cash_history,
    toIndex,
    status




"""

    Broker(cash::Real,market::Market)

The Order executing Unit in the System.


```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
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

broker(market::Market,cash::Real) = Broker(market,cash)



function broker(n_Assets::Int,cash::Real)
    M=market();
    foreach(x->addAsset!(M,asset()),1:n_Assets)
    return Broker(M,cash)
end

Base.show(io::IO,B::Broker) = print(io,"Broker with $(round(B.cash;digits=2)) funds and $(length(B.orders)) open orders")

"""

    placeOrder!(B::Broker,O::Order)

Place an Order in the Broker's Orderbook

```jldoctest
Random.seed!(1234);
B = broker(3,1000);
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
B = broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]]
O = Order(Buy(A,10))
placeOrder!(B,O)
processOrder!(B,O)
B.history
B.portfolio
```

"""
function processOrder!(B::Broker,O::Order,check_books::Bool=true)
    today = length(B)
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
    today = length(B)
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
B = broker(3,1000);
A = B.market.data[collect(keys(B.market.data))[2]] #Maybe write a getIndex for that
O = Order(Sell(A,10))
placeOrder!(B,O)
processOrder!(B,O)
requestToClose(B.portfolio[1])
resolvePortfolio!(B)
B.portfolio
length(B.history)

# output

2
```

"""
function resolvePortfolio!(B::Broker)
    for P in B.portfolio
        if P.requestToClose
            T = close(P, length(B)) 
            val = -value(T) #Negative because we are closing the position
            T.delta_cash = val
            if B.cash + val >= 0
                B.cash += val
                push!(B.history,T)
            else
                P.closed = false 
                #println("Not enough funds to close position") FIXME: This should maybe cancel the backtest or something
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
length(B.history)

# output

1

```
"""
function processOrders!(B::Broker)
    today = length(B)
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
x=asset();
y=asset();
M=market([x,y]);
B = broker(M,1000);
status(B)

# output

========================================
Date: 3651
Cash: 1000.0
Number of orders: 0
Number of positions: 0
Number of trades: 0
========================================
```
"""
function status(B::Broker,digits::Int=2)
    otp ="="^40*"\n"*"""
    Date: $(length(B))
    Cash: $(round(B.cash;digits=digits))
    Number of orders: $(length(B.orders))
    Number of positions: $(length(B.portfolio))
    Number of trades: $(length(B.history))
    """*"="^40
    print(otp)
    return
end

#TODO: This function needs documentation
function requestToCloseAll!(B::Broker)
    for P in B.portfolio
        requestToClose(P)
    end
    return
end

#TODO: This function needs documentation

"""
    length(B::Broker)

Return the length of the market the Broker is operating on.
"""
length(B::Broker) = length(B.market)

#TODO: This function needs documentation

"""
    cashHistory(B::Broker)

Return the cash history of the Broker

# Example
```julia
Random.seed!(1234);
M=market([asset(),asset()]);
T = Backtest(M,CrossOverStrategy,1000)
runTest(T)
cash_history(T.broker)
```
"""

function cash_history(B::Broker)
    cash_vector = Tuple{Int, Real}[(length(B),B.cash)]
    cash = B.cash
    for t in reverse(B.history)
        cash -= t.delta_cash
        push!(cash_vector,(t.date,cash))
    end
    push!(cash_vector,(1,cash))
    cash_vector = reverse(cash_vector) 
    return cash_vector
end

"""
    toIndex(B::Broker)::Asset

Convert a Broker to an Asset

```jldoctest
Random.seed!(1234);
x=asset();
y=asset();
M=market([x,y]);
B = broker(M,1000);
BT = Backtest(M,CrossOverStrategy,1000)
runTest(BT)
A = toIndex(BT.broker)
```

"""
function toIndex(B::Broker)::Asset
    cash = cash_history(B)
    n = cash[end][1]
    data = data_series(n)
    lastindex = 1
    nextindex = 1
    for (i,c) in cash
        nextindex = i
        data[1,lastindex:nextindex] .= c
        lastindex = nextindex
    end
    A = Asset("Broker",data,["Cash"])
    return A
end

"""
    plot(B::Broker)

Plot the cash history of the Broker

"""
function plot(B::Broker)
  plot(toIndex(B),"Cash")
end
