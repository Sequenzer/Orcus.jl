import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

from typing import Callable

from module.asset import Asset


# General Derivative class
class Derivative:
    def __init__(self,underlying:Asset,structure: Callable[[float], float],price:float,strike:float=None,name:str="None"):
        self.underlying = underlying
        self.f = structure
        self.name=name
        self.price=price
        self.strike=strike
    def plotReturn(self):
        t0= self.uValue
        size = np.abs(t0/10)
        t = np.arange(t0-size,t0+size, size/100)
        #add Axis
        plt.axhline(0, color='black')
        plt.axvline(self.uValue, color='black')
        #add Graph
        plt.plot(t,self.f(t)-self.price,"r")
        plt.plot(self.uValue,self.f(self.uValue)-self.price,"gx")
        
        plt.show()
    def printProps(self,withPlot=True):
        otp=f"""
        {'-'*40}
        Asset: {self.underlying.id}
        Derivative type: {self.name}
        Underlying value: {self.uValue}
        Derivative value: {self.value}
        Price paid: {self.price}
        Strike price: {self.strike}
        Absolute return: {self.absReturn}
        Percentage return: {self.pctReturn}
        Log return: {self.logReturn}
        {'-'*40}
        """
        print(otp)
        if withPlot:
            self.plotReturn()
        
    
    @property
    def uValue(self)-> float:
        return self.underlying.data.Close[-1]
    @property
    def value(self) -> float:
        return self.f(self.uValue)
    @property
    def absReturn(self) -> float:
        return self.f(self.uValue)-self.price
    @property
    def pctReturn(self) -> float:
        return self.absReturn/self.price
    @property
    def logReturn(self) -> float:
        if self.value<=0:
            return np.NINF
        return np.log(self.value/self.price)
    
#Special classes

class Buy(Derivative):
    def __init__(self,underlying:Asset,premium:float=0):
        pricePaid=underlying.data.Close[-1] + premium
        f = lambda x: x
        super().__init__(underlying,f,pricePaid,name="Buy")
        
class Sell(Derivative):
    def __init__(self,underlying:Asset,premium:float=0):
        pricePaid=-underlying.data.Close[-1] + premium
        f = lambda x: -x
        super().__init__(underlying,f,pricePaid,name="Sell")

class LongCall(Derivative):
    def __init__(self,underlying:Asset,strike:float,premium:float=0):
        pricePaid = premium
        f = lambda x : np.maximum(x-strike,0)
        super().__init__(underlying,f,pricePaid,strike,name="Long Call")

class LongPut(Derivative):
    def __init__(self,underlying:Asset,strike:float,premium:float=0):
        pricePaid = premium
        f = lambda x : np.maximum(-x+strike,0)
        super().__init__(underlying,f,pricePaid,strike,name="Long Put")

class ShortCall(Derivative):
    def __init__(self,underlying:Asset,strike:float,premium:float=0):
        pricePaid = -premium
        f = lambda x : np.minimum(-x+strike,0)
        super().__init__(underlying,f,pricePaid,strike,name="Short Call")
        
class ShortPut(Derivative):
    def __init__(self,underlying:Asset,strike:float,premium:float=0):
        pricePaid = -premium
        f = lambda x : np.minimum(+x-strike,0)
        super().__init__(underlying,f,pricePaid,strike,name="Short Pull")
        