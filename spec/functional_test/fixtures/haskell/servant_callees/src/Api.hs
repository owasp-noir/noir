{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Data.Text (Text)
import Servant

data User
data Health

type UserAPI =
       "users" :> Get '[JSON] [User]
  :<|> "users" :> Capture "userId" Integer :> Get '[JSON] User

type API =
       "v1" :> UserAPI
  :<|> "health" :> Get '[JSON] Health

server :: Server API
server =
       userServer
  :<|> healthServer

userServer :: Server UserAPI
userServer =
       listUsers
  :<|> getUser

healthServer :: Server ("health" :> Get '[JSON] Health)
healthServer = healthHandler

listUsers :: Handler [User]
listUsers = do
  users <- loadUsers
  audit "list"
  return users

getUser :: Integer -> Handler User
getUser userId = do
  user <- UserRepo.find userId
  case user of
    Just found -> return found
    Nothing -> throwError err404

healthHandler :: Handler Health
healthHandler = do
  status <- healthCheck
  return status
