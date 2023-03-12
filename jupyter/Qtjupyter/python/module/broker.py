import pandas as pd
import numpy as np

from module.asset import Asset
from module.market import Market
from module.closingOrder import ClosingOrder
from module.order import Order

class Broker:
    def __init__(self,*,cash: int, market: Market):
            self.positions= []
            self.trades=[]
            self.orders = []
            self.market = market
            self.cash = cash
    def placeOrder(self,order: Order) -> None:
        #ToDo Check if requirements for placement are met
        self.orders.append(order)
        return self
    def processOrders(self) -> None:
        if self.market.isEmpty:
            self.orders = []
            return
        for order in reversed(self.orders):
            try:
                self.processOrder(order)
                self.orders.remove(order)
                pass
            except Exception as e: 
                print(e)
                break
    def processOrder(self,order: Order) -> None:
        if type(order) is ClosingOrder:
            print("Closing Order is beeing processed")
            if -order.cashReturn<self.cash:
                cashToFulfill,trade = order.fulfill().values()
                self.cash -= cashToFulfill
                self.positions.remove(order.position)
                self.trades.append(trade)
            else:
                raise RuntimeError("Could not Pay for closing Order.")
        elif type(order) is Order:
            print("Opening Order is beeing processed")
            if -order.cashReturn<self.cash:
                cashToFulfill,trade,pos = order.fulfill().values()
                self.cash -= cashToFulfill
                self.positions.append(pos)
                self.trades.append(trade)
            else:
                raise RuntimeError("Could not Pay for opening Order.")
        else:
            raise TypeError("No Order Type specified")
        return self
    @property
    def status(self):
        otp=f"""
        {'-'*40}
        Date: {self.market.today}
        Cash: {self.cash}
        Number of orders: {len(self.orders)}
        Number of positions: {len(self.positions)}
        Number of trades: {len(self.trades)}
        {'-'*40}
        """
        print(otp)
        
    
        
         