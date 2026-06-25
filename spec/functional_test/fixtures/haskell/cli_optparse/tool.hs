module Main where

import Options.Applicative
import System.Environment (lookupEnv)

main :: IO ()
main = do
  _ <- execParser (info parser fullDesc)
  _ <- lookupEnv "API_TOKEN"
  return ()
  where
    parser = (,) <$> option auto ( long "port" <> short 'p' )
                 <*> switch ( long "verbose" )
    serveCmd = command "serve" (info (strOption ( long "host" )) fullDesc)
