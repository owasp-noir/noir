{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module ZOther where

import Servant

data Thing

server :: Server OtherAPI
server =
       wrongOne
  :<|> wrongTwo

wrongOne :: Handler Thing
wrongOne = do
  loadWrongOne

wrongTwo :: Handler Thing
wrongTwo = do
  loadWrongTwo
