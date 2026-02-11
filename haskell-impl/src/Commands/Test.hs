module Commands.Test
    ( runTestCommand
    ) where

import ProcessorTests
import WildcardPatternTests
import AdvancedPatternCacheTests
import PatternAnalyzerTests

-- | Run the test command
runTestCommand :: Maybe String -> Bool -> IO ()
runTestCommand maybePattern verbose = do
    when verbose $ putStrLn "Running 4917 Processor Tests..."
    
    putStrLn "=== 4917 Processor Test Suite ==="
    putStrLn ""
    
    (processorResults, wildcardResults, cacheResults, analyzerResults) <- case maybePattern of
        Nothing -> do
            putStrLn "Running all tests..."
            proc <- runAllTests
            wild <- runWildcardPatternTests
            cache <- runAdvancedPatternCacheTests
            analyzer <- runPatternAnalyzerTests
            return (proc, wild, cache, analyzer)
        Just pattern -> do
            putStrLn $ "Running tests matching pattern: " ++ pattern
            (proc, wild, cache, analyzer) <- runFilteredTests pattern
            return (proc, wild, cache, analyzer)
    
    let allResults = processorResults ++ wildcardResults ++ cacheResults ++ analyzerResults
        failures = filter (not . testPassed) allResults
        totalTests = length allResults
        passedTests = totalTests - length failures
    
    putStrLn ""
    putStrLn "=== Test Summary ==="
    putStrLn $ "✅ Passed: " ++ show passedTests ++ "/" ++ show totalTests
    
    if null failures
        then putStrLn "🎉 All tests passed!"
        else do
            putStrLn $ "❌ Failed: " ++ show (length failures) ++ " test(s)"
            putStrLn ""
            putStrLn "Failed tests:"
            mapM_ printFailedTest failures
  where
    printFailedTest test = putStrLn $ "  - " ++ testName test

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()

-- | Run filtered tests with pattern matching
runFilteredTests :: String -> IO ([TestResult], [TestResult], [TestResult], [TestResult])
runFilteredTests pattern = do
    putStrLn $ "Filtering tests by pattern: " ++ pattern
    
    allProcessorResults <- runAllTests
    allWildcardResults <- runWildcardPatternTests
    allCacheResults <- runAdvancedPatternCacheTests
    allAnalyzerResults <- runPatternAnalyzerTests
    
    let filteredProcessor = filter (matchesPattern pattern) allProcessorResults
        filteredWildcard = filter (matchesPattern pattern) allWildcardResults
        filteredCache = filter (matchesPattern pattern) allCacheResults
        filteredAnalyzer = filter (matchesPattern pattern) allAnalyzerResults
        
        totalFiltered = length filteredProcessor + length filteredWildcard + length filteredCache + length filteredAnalyzer
        totalAll = length allProcessorResults + length allWildcardResults + length allCacheResults + length allAnalyzerResults
    
    putStrLn $ "Matched " ++ show totalFiltered ++ " out of " ++ show totalAll ++ " tests"
    
    return (filteredProcessor, filteredWildcard, filteredCache, filteredAnalyzer)
  where
    -- Simple pattern matching - check if pattern is substring of test name (case-insensitive)
    matchesPattern :: String -> TestResult -> Bool
    matchesPattern pat test = 
        let lowerPat = map toLower pat
            lowerName = map toLower (testName test)
        in lowerPat `isInfixOf` lowerName
    
    toLower :: Char -> Char
    toLower c | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
              | otherwise = c
    
    isInfixOf :: Eq a => [a] -> [a] -> Bool
    isInfixOf [] _ = True
    isInfixOf _ [] = False
    isInfixOf needle haystack@(_:hs) = isPrefixOf needle haystack || isInfixOf needle hs
    
    isPrefixOf :: Eq a => [a] -> [a] -> Bool
    isPrefixOf [] _ = True
    isPrefixOf _ [] = False
    isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys