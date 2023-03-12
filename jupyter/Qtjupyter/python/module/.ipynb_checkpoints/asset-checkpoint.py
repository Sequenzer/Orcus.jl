import pandas as pd
import numpy as np
from datetime import date
import logging

def datafromcsv(Stock, start_date=np.datetime64(date(2000, 1, 1)), end_date=np.datetime64(date(2020, 1, 1))):
    data = pd.read_csv("src/"+ Stock + ".csv") #Change when implementing
    columns = ['Date', 'Volume', 'Open', 'High', 'Low', 'Close', 'adjclose']
    data.columns = columns
    data = data.set_index("Date")
    data.index= pd.to_datetime(data.index)
    data = data.sort_index()
    data = data.iloc[ lambda x: x.index > start_date] 
    data = data.iloc[ lambda x: x.index < end_date]
    return data

class Asset:
    def __init__(self,id: str, start=np.datetime64(date(2000, 1, 1)), end=np.datetime64(date(2020, 1, 1))):
            self.id = id
            if id == "empty":
                self.data=pd.DataFrame(columns=['Date', 'Volume', 'Open', 'High', 'Low', 'Close', 'adjclose'])
            else:
                try:
                    self.data=datafromcsv(id,start,end)
                except:
                    logging.warning("Can't find data for ID: %s ",id)
                    self.data=pd.DataFrame(columns=['Date', 'Volume', 'Open', 'High', 'Low', 'Close', 'adjclose'])
    def copy(self):
        A = Asset("empty")
        A.data =self.data.copy()
        return A
    def cut(self,i):
        A = Asset("empty")
        A.data =self.data.copy().iloc[:i]
        return A
    @property
    def last(self):
        return self.data.iloc[-1]
                