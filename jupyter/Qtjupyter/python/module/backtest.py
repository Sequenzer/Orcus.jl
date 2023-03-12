import pandas as pd
import numpy as np

from module.broker import Broker
from module.strategy import Strategy

class Backtest:
    def __init__(self,market,strategy, cash=100000):
        self.market=market
        self.broker = Broker(cash=cash,market=market)
        self.strategy = strategy(broker=self.broker,market=market,cash=cash)
    def process_day(self):
        self.broker.processOrders()
        self.strategy.init()
        self.strategy.next()
    def run(self):
        print(" 'Output': 'Running Backtest.'")
        try:
            for i in range(1, self.market.length):
                dailyMarket = self.market.getCutMarket(i)
                self.strategy.market = dailyMarket
                self.broker.market = dailyMarket
                self.process_day()
        except Exception as e:
            print(" 'Output': 'Error Detected.'")
            raise e

        finally:
            print(" 'Output': 'Backtest Complete.'")
