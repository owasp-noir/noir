{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Api where

import Data.Text (Text)
import Servant

data User
data Health
data Secret
data FileResponse

type UserAPI =
       "users" :> Get '[JSON] [User]
  :<|> "users" :> Capture "userId" Integer :> Get '[JSON] User
  :<|> "users" :> ReqBody '[JSON] User :> Post '[JSON] User
  :<|> "users" :> Capture "userId" Integer :> ReqBody '[JSON] User :> Put '[JSON] NoContent
  :<|> "users" :> Capture "userId" Integer :> Delete '[JSON] NoContent
  :<|> "search" :> QueryParam "q" Text :> Get '[JSON] [User]
  :<|> "files" :> CaptureAll "path" Text :> Get '[JSON] FileResponse
  :<|> Header "X-Token" Text :> "secure" :> Get '[JSON] Secret

type UploadAPI =
       "upload" :> MultipartForm Mem (MultipartData Mem) :> Post '[JSON] ()
  :<|> "stream" :> StreamGet NewlineFraming JSON (SourceIO String)
  :<|> "uverb"  :> UVerb 'PATCH '[200] '[User]

type API =
       "v1" :> UserAPI
  :<|> "v1" :> UploadAPI
  :<|> "health" :> Get '[JSON] Health
