{-# LANGUAGE OverloadedStrings #-}

-- `Test` is a production module namespace here, not a test tree.
module Test.Health where

import Web.Scotty

healthRoutes :: ScottyM ()
healthRoutes =
  get "/health" $ text "ok"
