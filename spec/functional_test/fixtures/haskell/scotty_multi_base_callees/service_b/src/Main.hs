module Main where

import Web.Scotty

main :: IO ()
main = scotty 3000 $ do
  get "/b" sharedHandler

sharedHandler :: ActionM ()
sharedHandler = do
  serviceB
  text "service-b"

serviceB :: ActionM ()
serviceB = pure ()
