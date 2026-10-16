{-# LANGUAGE OverloadedStrings #-}

module Main where

import Web.Scotty

main :: IO ()
main = scotty 3000 $ do
  get "/users/:id" $ do
    i <- pathParam "id"
    json (i :: Int)

  post "/users" $ do
    u <- jsonData
    json (u :: Int)
