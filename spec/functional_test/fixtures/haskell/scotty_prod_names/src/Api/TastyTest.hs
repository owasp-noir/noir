{-# LANGUAGE OverloadedStrings #-}

module Api.TastyTest where

import Test.Tasty
import Web.Scotty

-- A tasty-discover file kept next to the module it tests.
tests :: TestTree
tests = testGroup "tasty" []

stubApp = scottyApp $ do
  get "/tasty-stub" $ text "x"
