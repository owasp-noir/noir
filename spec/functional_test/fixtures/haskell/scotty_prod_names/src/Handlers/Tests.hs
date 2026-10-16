{-# LANGUAGE OverloadedStrings #-}

-- A quiz backend: "Tests" is the domain, not a test suite.
module Handlers.Tests where

import Web.Scotty

testsRoutes :: ScottyM ()
testsRoutes =
  get "/tests" $ text "[]"
