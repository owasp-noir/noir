{-# LANGUAGE OverloadedStrings #-}

-- A bandwidth speed-test endpoint, served by the app.
module Api.SpeedTest where

import Web.Scotty

speedTestRoutes :: ScottyM ()
speedTestRoutes =
  get "/speedtest" $ text "ok"
