{-# LANGUAGE OverloadedStrings #-}

module Main where

import Web.Scotty
import Data.Text.Lazy (Text)

main :: IO ()
main = scotty 3000 $ do
  get "/" $ do
    text "ok"

  get "/users" $ do
    q <- queryParam "q"
    json q

  post "/users" $ do
    u <- jsonData
    json u

  get "/users/:id" $ do
    i <- pathParam "id"
    json i

  put "/users/:id" $ do
    name <- formParam "name"
    text name

  delete "/users/:id" $ do
    text "deleted"

  patch "/users/:id" $ do
    token <- header "X-Token"
    text "patched"

  options "/users" $ text "opt"

  addroute GET "/health" $ text "healthy"

  get "/search" listMatches

listMatches :: ActionM ()
listMatches = do
  term <- queryParam "term"
  json term
