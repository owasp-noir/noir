{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Hspec
import qualified Web.Scotty as Scotty

testApp = Scotty.scottyApp $ do
  Scotty.get "/test-dir-stub" $ Scotty.text "stub"

main :: IO ()
main = hspec $ pure ()
