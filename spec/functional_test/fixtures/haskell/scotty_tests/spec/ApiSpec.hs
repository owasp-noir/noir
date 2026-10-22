{-# LANGUAGE OverloadedStrings #-}

module ApiSpec where

import Test.Hspec
import Test.Hspec.Wai

spec :: Spec
spec = describe "api" $
  it "is up" $
    get "/spec-dir-only" `shouldRespondWith` 200
