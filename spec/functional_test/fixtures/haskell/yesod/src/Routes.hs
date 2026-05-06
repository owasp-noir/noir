{-# LANGUAGE TemplateHaskell #-}

module Routes where

import Yesod

mkYesodData "App" $(parseRoutesFile "config/routes.yesodroutes")
