{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Servant

data Status

type API = "service-b" :> Get '[JSON] Status
