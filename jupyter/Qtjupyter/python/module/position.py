import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

from module.asset import Asset
from module.market import Market
from module.trade import Trade
from module.closingOrder import ClosingOrder
from module.derivative import Derivative

class Position:
    def __init__(self,trade: Trade):
        self.underlying = trade.underlying
        self.volume =trade.volume
        self.trade = trade
        self.derivative = trade.derivative
        self.closed = False
    def plotReturn(self):
        t0= self.derivative.uValue
        size = np.abs(t0/10)
        t = np.arange(t0-size,t0+size, size/100)
        #add Axis
        plt.axhline(0, color='black')
        plt.axvline(t0, color='black')
        #add Graph
        plt.plot(t,(self.derivative.f(t)-self.derivative.price)*self.volume,"r")
        plt.plot(t0,(self.derivative.f(t0)-self.derivative.price)*self.volume,"gx")
        
        plt.show()
    def printProps(self,withPlot=True):
        otp=f"""
        {'-'*40}
        Asset: {self.underlying.id}
        Positions type: {self.derivative.name}
        Opening Date: {self.trade.date}
        Underlying value: {self.derivative.uValue}
        Position value: {self.value}
        Amount: {self.volume}
        Price paid: {self.price}
        Strike price: {self.strike}
        Absolute return: {self.absReturn}
        Percentage return: {self.pctReturn}
        Log return: {self.logReturn}
        Currently closed: {self.closed}
        {'-'*40}
        """
        print(otp)
        if withPlot:
            self.plotReturn()
        
    
    
    @property
    def value(self) -> float:
        return self.volume*self.derivative.value
    @property
    def price(self)-> float:
        return self.derivative.price*self.volume
    @property
    def strike(self)-> float:
        return self.derivative.strike
    @property
    def absReturn(self)-> float:
        return self.derivative.absReturn*self.volume
    @property
    def pctReturn(self)-> float:
        return self.derivative.pctReturn
    @property
    def logReturn(self) -> float:
        if self.value<=0:
            return np.NINF
        return np.log(self.value/self.price)
    
    def getClosingOrder(self):
        if self.closed:
            return
        return ClosingOrder(self)
    def close(self) -> None:
        self.close = True
        