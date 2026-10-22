module Main where

import Turtle (options, optText, optInt, optPath, switch, arg, argText)
import System.Environment (lookupEnv)

parser = (,,,,) <$> optText "name" 'n' "your name"
                <*> optInt "age" 'a' "your age"
                <*> optPath "config" 'c' "config file"
                <*> switch "verbose" 'v' "be verbose"
                <*> argText "target" "target host"

main :: IO ()
main = do
  (name, age, cfg, verbose, target) <- options "Greeting script" parser
  _ <- lookupEnv "GREETING_TOKEN"
  return ()
