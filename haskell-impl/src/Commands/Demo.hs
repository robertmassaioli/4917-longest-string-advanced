module Commands.Demo
    ( runDemoCommand
    ) where

import Processor
import BruteForceSearch
import qualified Processor as P

-- | Run the demo command  
runDemoCommand :: Maybe Int -> Bool -> IO ()
runDemoCommand maybeLength verbose = do
    when verbose $ putStrLn "Running 4917 Processor demonstration..."
    
    putStrLn "=== 4917 Processor Demonstration ==="
    putStrLn "This demo shows the processor capabilities and program search."
    putStrLn ""
    
    -- Basic processor demonstration
    putStrLn "🔧 Basic Processor Test:"
    basicProcessorDemo
    putStrLn ""
    
    case maybeLength of
        Nothing -> do
            putStrLn "🔍 Brute Force Search (Lengths 1-6):"
            demonstrateBruteForceSearch
        Just len -> do
            putStrLn $ "🔍 Brute Force Search (Length " ++ show len ++ "):"
            demonstrateSingleLength len
    
    putStrLn ""
    putStrLn "✨ Demo completed!"

-- | Basic processor functionality demo
basicProcessorDemo :: IO ()
basicProcessorDemo = do
    putStrLn "Creating a simple program: [8, 15, 0] (PRINT 15, HALT)"
    let device = createDevice [8, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    
    -- Run with loop detection
    let loopCheckResult = runProgramLoopCheck device
    case loopCheckResult of
        ProgramTerminated count -> putStrLn $ "Program terminated normally with " ++ show count ++ " characters output"
        InfiniteLoopDetected -> putStrLn "Infinite loop detected!"

-- | Demonstrate brute force search for lengths 1-6  
demonstrateBruteForceSearch :: IO ()
demonstrateBruteForceSearch = do
    putStrLn "Searching for optimal programs at each length..."
    
    -- Search through lengths 1-6 with timing and analysis
    mapM_ searchAndAnalyze [1..6]

-- | Demonstrate search for a single length
demonstrateSingleLength :: Int -> IO ()
demonstrateSingleLength len = do
    putStrLn $ "Searching for optimal programs of length " ++ show len ++ "..."
    searchAndAnalyze len

-- | Search and analyze a specific program length
searchAndAnalyze :: Int -> IO ()
searchAndAnalyze len = do
    putStr $ "Length " ++ show len ++ ": "
    result <- findLongestOutputProgramTimed len
    
    case bestProgram result of
        Nothing -> putStrLn "No programs found that produce output"
        Just prog -> do
            putStrLn $ show (programBytes prog) ++ " → " ++ show (outputLength prog) ++ " chars"
            putStrLn $ "  (" ++ show (programsWithOutput result) ++ "/" ++ 
                      show (programsTested result) ++ " programs produced output, " ++
                      show (searchTimeMs result) ++ "ms)"

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action  
when False _ = return ()