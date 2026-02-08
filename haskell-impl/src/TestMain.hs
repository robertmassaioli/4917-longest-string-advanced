module Main where

import ProcessorTests
import System.Exit

main :: IO ()
main = do
    results <- runAllTests
    let failures = filter (not . testPassed) results
    if null failures
    then exitSuccess
    else exitWith (ExitFailure 1)