module Handler.Home where

import Yesod

getSharedR :: Handler Html
getSharedR = do
  serviceB
  defaultLayout [whamlet|service-b|]

serviceB :: Handler ()
serviceB = pure ()
