import pandas as pd
import numpy as np

from typing import Literal

from module.trade import Trade

    
class ClosingOrder:
    def __init__(self,position):
        self.position=position
        self.volume= self.position.volume
        self.underlying=self.position.underlying
        self.derivative=self.position.derivative
    def fulfill(self):
        trade = Trade(self.derivative,self.underlying.data.index[-1],self.volume,closing=True)
        self.position.close()
        cash = self.cashReturn
        return {"cash":cash,"trade":trade}
    def printProps(self):
        #Temporary
        self.derivative.printProps()
    @property
    def cashReturn(self):
        return self.position.value