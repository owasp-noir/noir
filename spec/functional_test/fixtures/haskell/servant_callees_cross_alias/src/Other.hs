{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Other where

import Servant

data Thing

usersServer :: Server OtherAPI
usersServer = otherHandler

otherHandler :: Handler Thing
otherHandler = do
  loadOtherUsers
