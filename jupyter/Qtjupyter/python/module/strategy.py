import pandas as pd
import numpy as np

from abc import abstractmethod, ABCMeta

class Strategy(metaclass=ABCMeta):
    def __init__(self, broker, market=None, cash=None):
        self.market = market
        self.indicators = []
        self.broker = broker
        self.order = None

    def I(self, indicator_function, data, *args, **kwargs):
        indicator = indicator_function(data, *args, **kwargs)
        self.indicators.append(indicator)
        return indicator

    @abstractmethod
    def init(self):
        pass

    @abstractmethod
    def next(self):
        pass

    def get_order(self):
        self.order = None
        self.init()
        self.next()
        self._broker.process_orders()
        return self._broker.trades

#     def buy(self):
#         return self.broker.new_order(self._broker._cash, "buy")

#     def sell(self):
#         return self.broker.new_order(self._broker._cash, "sell")

    @property
    def position(self):
        return self.broker.positions

    @property
    def orders(self):
        return self.broker.orders

    @property
    def trades(self):
        return self.broker.trades
    @property
    def cash(self):
        return self.broker.cash