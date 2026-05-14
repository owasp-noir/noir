{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Servant

data Thing

type PublicAPI = "public" :> Get '[JSON] Thing

type AdminAPI = "admin" :> Get '[JSON] Thing

server :: Server PublicAPI
server = publicHandler

publicHandler :: Handler Thing
publicHandler = do
  loadPublic

adminHandler :: Handler Thing
adminHandler = do
  loadAdmin
