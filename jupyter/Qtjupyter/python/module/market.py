import pandas as pd
import numpy as np
from typing import Type

from module.asset import Asset

def addData(d,column):
    return pd.DataFrame({ asset.id: asset.data[column] for asset in d.values()})



class Market:
    def __init__(self):
            self.assets: dict[str,Asset] = {}
    def addAsset(self,asset: Asset) -> None:
        self.assets[asset.id]=asset
    def addAssets(self,listOfAssets) -> None:
        for asset in listOfAssets:
            self.addAsset(asset)
    def cutAll(self,i):
        for asset in self.assets:
            self.assets[asset].data=self.assets[asset].data.iloc[:i]
    def getCutData(self,i) -> None:
        cutData= {}
        for asset in self.assets:
            cutData[asset]=self.assets[asset].cut(i)
        return cutData
    def getCutMarket(self,i):
        M = Market()
        M.assets=self.getCutData(i)
        return M
    def getDataByColumn(self,column) -> pd.DataFrame:
        return pd.DataFrame({ asset.id: asset.data[column] for asset in self.assets.values()})
    def getMarketVolume(self) -> pd.DataFrame:
        return pd.DataFrame(self.getDataByColumn("Volume").sum(axis=1),columns=["Volume"])
    def getMarketValue(self) -> pd.DataFrame:
        assetVolumes = self.getDataByColumn("Volume")
        assetPrices = self.getDataByColumn("Close")
        return  pd.DataFrame(assetVolumes.mul(assetPrices).sum(axis=1),columns=["Value"])
    @property
    def today(self):
        return np.max([asset.data.index.max() for asset in self.assets.values()]) #Maximum for now check in the future if all are the same
    @property
    def length(self) -> int:
         return np.max([len(asset.data.index)for asset in self.assets.values()]) #Maximum for now check in the future if all are the same
    @property
    def isEmpty(self) -> bool:
        return type(list(self.assets.values())[0])!=Asset
    