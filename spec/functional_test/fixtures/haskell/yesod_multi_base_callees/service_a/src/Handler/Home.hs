module Handler.Home where

import Yesod

getSharedR :: Handler Html
getSharedR = do
  serviceA
  defaultLayout [whamlet|service-a|]

serviceA :: Handler ()
serviceA = pure ()
