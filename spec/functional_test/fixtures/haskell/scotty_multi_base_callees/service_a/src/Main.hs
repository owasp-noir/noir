module Main where

import Web.Scotty

main :: IO ()
main = scotty 3000 $ do
  get "/a" sharedHandler

sharedHandler :: ActionM ()
sharedHandler = do
  serviceA
  text "service-a"

serviceA :: ActionM ()
serviceA = pure ()
