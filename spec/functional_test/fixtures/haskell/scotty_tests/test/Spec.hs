{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Hspec
import Test.Hspec.Wai
import qualified Web.Scotty as Scotty

testApp = Scotty.scottyApp $ do
  Scotty.get "/stub-only" $ Scotty.text "stub"

main :: IO ()
main = hspec $ with testApp $
  describe "GET /users/42" $
    it "responds" $ do
      get "/users/42" `shouldRespondWith` 200
      post "/users" "" `shouldRespondWith` 201
