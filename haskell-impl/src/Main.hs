module Main where

import CLI (parseCommand, runCommand)

main :: IO ()
main = do
    command <- parseCommand
    runCommand command