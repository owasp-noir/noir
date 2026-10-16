{-# LANGUAGE OverloadedStrings #-}

module App.WaiHelper where

import Test.Hspec.Wai
import Test.Hspec.Wai.Extra ()

-- A test helper that lives outside any test directory; the hspec-wai import
-- is what marks it as test code.
helperRequest :: WaiSession st a
helperRequest = do
  get "/wai-helper-only"
  undefined
