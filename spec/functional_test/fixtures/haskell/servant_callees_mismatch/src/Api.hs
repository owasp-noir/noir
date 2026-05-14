{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Servant

data Thing

type API =
       "one" :> Get '[JSON] Thing
  :<|> "two" :> Get '[JSON] Thing

server :: Server API
server = onlyHandler

onlyHandler :: Handler Thing
onlyHandler = do
  value <- loadThing
  return value
