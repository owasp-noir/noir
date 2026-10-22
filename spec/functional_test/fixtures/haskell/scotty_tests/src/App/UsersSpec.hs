{-# LANGUAGE OverloadedStrings #-}

module App.UsersSpec where

import Test.Hspec
import Web.Scotty

-- An hspec-discover file kept next to the module it tests.
spec :: Spec
spec = describe "users" $
  it "stubs a route" $ do
    let _ = scottyApp $ do
          get "/spec-suffix-only" $ text "x"
    pure ()
