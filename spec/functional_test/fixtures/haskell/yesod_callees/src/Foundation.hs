{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Foundation where

import Yesod

data App = App

mkYesodData "App" [parseRoutes|
/ HomeR GET
/blog/#Text BlogPostR GET POST
/faq FaqR
/api ApiR:
    /health HealthR GET
|]
