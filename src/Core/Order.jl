
export 
    Order,
    order,
    price,
    fulfill,
    volume,
    isfulfilled


"""
    Order(derivative::Derivative, volume::Real=1)

An order to buy or sell a derivative, not yet fulfilled.

```jldoctest
A=asset();
B=Buy(A,10);
O=order(B);
O.fulfilled
# output

false
```
"""
mutable struct Order{D<:Derivative}
    derivative::D
    volume::Float64
    fulfilled::Bool
    fulfillment_date::Int

    function Order(derivative::D, volume::Real=1) where {D<:Derivative}
        this = new{D}()
        this.derivative = derivative
        this.volume = Float64(volume)
        this.fulfilled = false
        return this
    end
end

order(derivative::Derivative, volume::Real=1) = Order(derivative,volume)

Base.show(io::IO,O::Order) = print(io,"Order for $(O.volume) $(name(O.derivative)) on $(O.derivative.underlying.ticker)")


volume(order::Order) = order.volume

"""
    price(order::Order,date::DateTime=now()) 

The price of a placed Order, can be negative.

```jldoctest
Random.seed!(1234);
A=asset();
B=Buy(A,10);
O=order(B,10);
price(O)
# output

1080.1689673025153
```
"""
price(order::Order) = price(order.derivative) * volume(order)


"""    
    fulfill(order::Order,date::DateTime=now())

Fulfill an Order, returns the price of the Order.

```jldoctest
Random.seed!(1234);
A=asset();
B=Buy(A,10);
O=Order(B,10);
fulfill(O,100)
# output

1202.1778063564075
```
"""
function fulfill(order::Order,date::Int=length(order.derivative.underlying))
    order.fulfilled = true
    order.fulfillment_date = date
    return price(order) 
end


"""
    isfulfilled(order::Order)

Returns true if the Order has been fulfilled.

```jldoctest
Random.seed!(1234);
A=asset();
B=Buy(A,10);
O=Order(B,10);
isfulfilled(O)
# output

false
```
"""
isfulfilled(order::Order) = order.fulfilled



    


