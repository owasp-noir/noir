{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Servant
import Servant.API.Generic ((:-))

data Item
data Detail

-- A record-based (NamedRoutes / Servant.API.Generic) API. Each field is a route
-- declared as `field :: mode :- <route>`. `otherRoutes` nests another record via
-- `NamedRoutes`, prefixed by the captured `itemId`.
data Routes mode = Routes
  { version :: mode :- "version" :> Get '[JSON] Item
  , listItems :: mode :- "items" :> QueryParam "page" Int :> Get '[JSON] [Item]
  , createItem :: mode :- "items" :> ReqBody '[JSON] Item :> Post '[JSON] Item
  , itemRoutes :: mode :- "items" :> Capture "itemId" Int :> NamedRoutes ItemRoutes
  }

newtype ItemRoutes mode = ItemRoutes
  { detail :: mode :- "detail" :> Get '[JSON] Detail
  }

type API = NamedRoutes Routes
