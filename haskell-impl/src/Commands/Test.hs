module Commands.Test
    ( runTestCommand
    ) where

import ProcessorTests

-- | Run the test command
runTestCommand :: Maybe String -> Bool -> IO ()
runTestCommand maybePattern verbose = do
    when verbose $ putStrLn "Running 4917 Processor Tests..."
    
    putStrLn "=== 4917 Processor Test Suite ==="
    putStrLn ""
    
    results <- case maybePattern of
        Nothing -> do
            putStrLn "Running all tests..."
            runAllTests
        Just pattern -> do
            putStrLn $ "Running tests matching pattern: " ++ pattern
            runFilteredTests pattern
    
    putStrLn ""
    let failures = filter (not . testPassed) results
    if null failures
        then putStrLn "✅ All tests passed!"
        else putStrLn $ "❌ " ++ show (length failures) ++ " test(s) failed"

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()

-- | Run filtered tests (placeholder for pattern matching)
runFilteredTests :: String -> IO [TestResult]
runFilteredTests _pattern = do
    putStrLn "Note: Pattern filtering not yet implemented, running all tests..."
    runAllTests