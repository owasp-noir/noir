{-# LANGUAGE OverloadedStrings #-}

module Api.BillingSpec where

import Test.Hspec
import Web.Scotty

-- An hspec-discover file kept next to the module it tests.
spec :: Spec
spec = describe "billing" $
  it "stubs a route" $ do
    let _ = scottyApp $ do
          get "/billing-spec-stub" $ text "x"
    pure ()
