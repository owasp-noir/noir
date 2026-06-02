module Handlers where

rates :: Service -> Handler [Rate]
rates s = do
  found <- lookupRates s
  return found

allRates :: Handler [Rate]
allRates = do
  loaded <- loadAllRates
  return loaded
