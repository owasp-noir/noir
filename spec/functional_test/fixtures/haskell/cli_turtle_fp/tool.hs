module Main where

import Turtle (options, optText, argText, arg, argInt)
import qualified Turtle
import Text.Read (readMaybe)
import qualified Data.Text as Text
import System.Environment (lookupEnv)

-- arg count "deprecated" old code

-- | Locally-defined dispatch helper that happens to share Turtle.switch's
-- name; unrelated to CLI option parsing (Turtle.switch is used qualified
-- below, so there is no name clash).
switch :: String -> Bool
switch "on" = True
switch "staging" = False
switch _ = False

logMessage :: Int -> String -> String -> IO ()
logMessage code level msg = putStrLn (show code ++ " [" ++ level ++ "] " ++ msg)

emitWarning :: IO ()
emitWarning = do
  let arg = 42
      level = "WARN"
  logMessage arg level "urgent"

parser = (,,,,) <$> optText "name" 'n' "your name"
                <*> Turtle.switch "verbose" 'v' "be verbose"
                <*> argText "target" "target host"
                <*> argInt "retries" "number of retries"
                <*> arg (readMaybe . Text.unpack) "count" "how many times"

main :: IO ()
main = do
  (name, verbose, target, retries, count) <- options "Greeting script" parser
  emitWarning
  putStrLn (if switch "staging" then "staging" else "prod")
  _ <- lookupEnv "GREETING_TOKEN"
  return ()
