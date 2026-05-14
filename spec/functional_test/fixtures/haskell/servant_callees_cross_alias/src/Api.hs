{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Servant

data Thing

type API =
       "users" :> Get '[JSON] Thing
  :<|> "health" :> Get '[JSON] Thing

server :: Server API
server =
       usersServer
  :<|> healthHandler

healthHandler :: Handler Thing
healthHandler = do
  healthCheck
