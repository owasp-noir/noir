{-# LANGUAGE OverloadedStrings #-}

-- "Spec" here is the OpenAPI specification, not a test.
module Api.OpenApiSpec where

import Web.Scotty

openApiRoutes :: ScottyM ()
openApiRoutes =
  get "/openapi.json" $ text "{}"
