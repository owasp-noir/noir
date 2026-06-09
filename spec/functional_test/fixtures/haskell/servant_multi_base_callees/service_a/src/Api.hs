module Api where

import Servant

type API = "a" :> Get '[JSON] String

server :: Server API
server = sharedHandler

sharedHandler :: Handler String
sharedHandler = do
  serviceA
  pure "service-a"

serviceA :: Handler ()
serviceA = pure ()
