module Api where

import Servant

type API = "b" :> Get '[JSON] String

server :: Server API
server = sharedHandler

sharedHandler :: Handler String
sharedHandler = do
  serviceB
  pure "service-b"

serviceB :: Handler ()
serviceB = pure ()
