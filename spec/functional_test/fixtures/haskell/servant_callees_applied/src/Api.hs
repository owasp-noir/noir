{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Servant
import qualified Handlers as H

data Info
data Rate

type RatesAPI =
       "rates" :> Get '[JSON] [Rate]
       -- a full-line comment sitting between routes must not truncate the alias
  :<|> "rates" :> "all" :> Get '[JSON] [Rate]

type API =
       "info" :> Get '[JSON] Info   -- a trailing comment on the first route

  :<|> RatesAPI

-- The server is named arbitrarily (not `server` / `apiServer`); it is found via
-- its `:: Server API` signature. Its leaves are an application (`return x`), a
-- qualified application (`H.rates s`) and a qualified value (`H.allRates`).
exchangeServer :: Service -> Server API
exchangeServer s = return apiInfo :<|> H.rates s :<|> H.allRates

-- A binding whose body carries an inline `::` annotation is still a definition,
-- so its callees (here `buildInfo`) must be extracted.
apiInfo :: Info
apiInfo = buildInfo (Proxy :: Proxy API)
