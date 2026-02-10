module Commands.Search
    ( runSearchCommand
    ) where

import BruteForceSearch
import Text.Printf
import Data.Word (Word8)

-- | Run the search command
runSearchCommand :: Int -> Bool -> Bool -> Bool -> IO ()
runSearchCommand searchLength useCached useAdvanced verbose = do
    when verbose $ putStrLn $ "Searching for optimal programs of length " ++ show searchLength
    
    putStrLn $ "=== Program Search (Length " ++ show searchLength ++ ") ==="
    putStrLn $ "Searching " ++ show (16^searchLength) ++ " possible programs..."
    putStrLn ""
    
    result <- if useAdvanced
              then do
                  when verbose $ putStrLn "Using Phase 2 advanced pattern analysis..."
                  cachedResult <- findLongestOutputProgramAdvanced searchLength
                  return $ convertCachedResult cachedResult
              else if useCached 
              then do
                  when verbose $ putStrLn "Using persistent memoization cache..."
                  cachedResult <- findLongestOutputProgramCached searchLength
                  return $ convertCachedResult cachedResult
              else do
                  when verbose $ putStrLn "Running direct search..."
                  findLongestOutputProgramTimed searchLength
    
    case bestProgram result of
        Nothing -> do
            putStrLn "❌ No programs found that produce output"
            putStrLn $ "   Tested " ++ show (programsTested result) ++ " programs in " ++
                      printf "%.1fms" (searchTimeMs result)
        Just prog -> do
            putStrLn $ "✅ Best program found: " ++ show (programBytes prog)
            putStrLn $ "   Output length: " ++ show (outputLength prog) ++ " characters"
            putStrLn $ "   Programs with output: " ++ show (programsWithOutput result) ++ "/" ++ 
                      show (programsTested result) ++ " (" ++
                      printf "%.1f%%" (fromIntegral (programsWithOutput result) / fromIntegral (programsTested result) * 100 :: Double) ++ ")"
            putStrLn $ "   Search time: " ++ printf "%.1fms" (searchTimeMs result)
            
            when verbose $ do
                putStrLn ""
                putStrLn "Program analysis:"
                analyzeProgram (programBytes prog)

-- | Convert cached search result to standard search result
convertCachedResult :: CachedSearchResult -> SearchResult
convertCachedResult cached = SearchResult
    { bestProgram = cachedBestProgram cached
    , searchTimeMs = cachedSearchTimeMs cached
    , programsTested = cachedProgramsTested cached
    , programsWithOutput = cachedProgramsWithOutput cached
    }

-- | Analyze a program and explain what it does (basic analysis)
analyzeProgram :: [Word8] -> IO ()
analyzeProgram program = do
    putStrLn "Instruction breakdown:"
    mapM_ analyzeInstruction (zip [0..] (map fromIntegral program))
  where
    analyzeInstruction (addr, inst) = do
        putStrLn $ "  " ++ show addr ++ ": " ++ show inst ++ " - " ++ instructionDescription inst

-- | Get description for an instruction
instructionDescription :: Int -> String
instructionDescription 0  = "HALT"
instructionDescription 1  = "R0 = R0 + R1"
instructionDescription 2  = "R0 = R0 - R1"
instructionDescription 3  = "R0++"
instructionDescription 4  = "R1++"
instructionDescription 5  = "R0--"
instructionDescription 6  = "R1--"
instructionDescription 7  = "Ring Bell (NOP)"
instructionDescription 8  = "PRINT (needs operand)"
instructionDescription 9  = "LOAD R0 (needs address)"
instructionDescription 10 = "LOAD R1 (needs address)"
instructionDescription 11 = "STORE R0 (needs address)"
instructionDescription 12 = "STORE R1 (needs address)"
instructionDescription 13 = "JUMP (needs address)"
instructionDescription 14 = "JUMP IF R0==0 (needs address)"
instructionDescription 15 = "JUMP IF R0!=0 (needs address)"
instructionDescription n   = "Unknown instruction (" ++ show n ++ ")"

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()