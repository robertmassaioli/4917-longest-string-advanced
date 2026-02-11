module Main where

import ProcessorTests
import WildcardPatternTests
import AdvancedPatternCacheTests
import System.Exit

main :: IO ()
main = do
    putStrLn "=== 4917 Processor Complete Test Suite ==="
    putStrLn ""
    
    -- Run processor tests
    putStrLn "🔧 Running Processor Tests..."
    processorResults <- runAllTests
    
    -- Run wildcard pattern tests
    wildcardResults <- runWildcardPatternTests
    
    -- Run advanced pattern cache tests
    cacheResults <- runAdvancedPatternCacheTests
    
    let allResults = processorResults ++ wildcardResults ++ cacheResults
        failures = filter (not . testPassed) allResults
        totalTests = length allResults
        passedTests = totalTests - length failures
    
    putStrLn ""
    putStrLn "=== Test Summary ==="
    putStrLn $ "✅ Passed: " ++ show passedTests ++ "/" ++ show totalTests
    
    if null failures
    then do
        putStrLn "🎉 All tests passed!"
        exitSuccess
    else do
        putStrLn $ "❌ Failed: " ++ show (length failures) ++ " test(s)"
        putStrLn ""
        putStrLn "Failed tests:"
        mapM_ printFailedTest failures
        exitWith (ExitFailure 1)
  where
    printFailedTest test = putStrLn $ "  - " ++ testName test