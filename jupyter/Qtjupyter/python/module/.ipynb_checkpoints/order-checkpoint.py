import pandas as pd
import numpy as np

from typing import Literal

from module.derivative import Derivative
from module.trade import Trade
from module.position import Position

class Order:
    def __init__(self,derivative: Derivative,volume:int=1):
        self.underlying = derivative.underlying
        self.derivative = derivative
        self.volume = volume
    def fulfill(self):
        trade = Trade(self.derivative,self.underlying.data.index[-1],self.volume,closing=False)
        position = Position(trade)
        cash = self.cashReturn
        return {"cash": cash,"trade":trade, "pos":position}
    def printProps(self):
        #Temporary
        self.derivative.printProps()
    @property
    def cashReturn(self):
        return -self.derivative.price*self.volume
