import pandas as pd
import numpy as np
from datetime import date

from typing import Literal

from module.derivative import Derivative

class Trade:
    def __init__(self,derivative: Derivative , date: date = date.today(), volume:int=1, closing: bool=False, trade_data:dict={}):
        self.underlying = derivative.underlying
        self.derivative = derivative
        self.date = date
        self.volume=volume
        self.trade_data = trade_data