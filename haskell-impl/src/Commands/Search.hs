{-# LANGUAGE RecordWildCards #-}

module Commands.Search
    ( runSearchCommand
    ) where

import BruteForceSearch
import InstructionAnalysis (analyzeProgram)
import qualified ExecutionTracing as ET
import Text.Printf
import Data.Word (Word8)
import System.IO.Error (tryIOError)
import System.Directory (removeFile, doesFileExist)

-- | Run the search command (always uses advanced caching)
runSearchCommand :: Int -> Bool -> String -> Bool -> IO ()
runSearchCommand searchLength fresh cacheFile verbose = do
    when verbose $ putStrLn $ "Searching for optimal programs of length " ++ show searchLength
    
    -- Handle fresh cache option
    when fresh $ do
        when verbose $ putStrLn $ "Deleting existing cache file: " ++ cacheFile
        fileExists <- doesFileExist cacheFile
        if fileExists
            then do
                result <- tryIOError $ removeFile cacheFile
                case result of
                    Left err -> putStrLn $ "Warning: Could not delete cache file: " ++ show err
                    Right _ -> when verbose $ putStrLn "Cache file deleted successfully"
            else when verbose $ putStrLn "Cache file does not exist (starting fresh automatically)"
    
    when verbose $ do
        putStrLn $ "Using cache file: " ++ cacheFile
        putStrLn "Using advanced pattern analysis with persistent caching"
    
    putStrLn $ "=== Program Search (Length " ++ show searchLength ++ ") ==="
    putStrLn $ "Searching " ++ show (16^searchLength) ++ " possible programs..."
    putStrLn ""
    
    when verbose $ putStrLn "Running advanced pattern analysis with persistent caching..."
    cachedResult <- findLongestOutputProgramAdvanced cacheFile searchLength
    
    case cachedBestProgram cachedResult of
        Nothing -> do
            putStrLn "❌ No programs found that produce output"
            putStrLn $ "   Tested " ++ show (cachedProgramsTested cachedResult) ++ " programs in " ++
                      printf "%.1fms" (cachedSearchTimeMs cachedResult)
        Just prog -> do
            putStrLn $ "✅ Best program found: " ++ show (ET.resultProgram prog)
            putStrLn $ "   Output length: " ++ show (ET.resultOutput prog) ++ " characters"
            putStrLn $ "   Programs with output: " ++ show (cachedProgramsWithOutput cachedResult) ++ "/" ++ 
                      show (cachedProgramsTested cachedResult) ++ " (" ++
                      printf "%.1f%%" (fromIntegral (cachedProgramsWithOutput cachedResult) / fromIntegral (cachedProgramsTested cachedResult) * 100 :: Double) ++ ")"
            putStrLn $ "   Search time: " ++ printf "%.1fms" (cachedSearchTimeMs cachedResult)
            
            when verbose $ do
                putStrLn ""
                putStrLn "Program analysis:"
                analyzeProgram (ET.resultProgram prog)
    
    -- Display cache statistics (always available with advanced caching)
    putStrLn ""
    displayCacheStatistics cachedResult
    
    putStrLn ""
    putStrLn $ "💾 Cache file '" ++ cacheFile ++ "' updated."
    putStrLn "🔄 Run again to benefit from cached results!"


-- | Display cache effectiveness statistics
displayCacheStatistics :: CachedSearchResult -> IO ()
displayCacheStatistics CachedSearchResult{..} = do
    putStrLn "📊 Cache Effectiveness Statistics:"
    
    -- Calculate cache effectiveness percentage
    let totalLookups = cachedCacheHits + cachedCacheMisses
        effectivenessPercent = if totalLookups > 0 
                              then fromIntegral cachedExecutionsSaved / fromIntegral totalLookups * 100 
                              else 0 :: Double
    
    putStrLn $ "   Cache hit rate: " ++ show cachedCacheHits ++ "/" ++ show totalLookups ++ 
              " (" ++ printf "%.1f%%" (fromIntegral cachedCacheHits / fromIntegral totalLookups * 100 :: Double) ++ ")"
    
    putStrLn $ "   Executions saved: " ++ show cachedExecutionsSaved ++ 
              " (" ++ printf "%.1f%%" effectivenessPercent ++ ")"
    
    when (cachedWildcardHits > 0) $
        putStrLn $ "   Wildcard pattern hits: " ++ show cachedWildcardHits
    
    when (cachedSimilarityHits > 0) $
        putStrLn $ "   Similarity hits: " ++ show cachedSimilarityHits
    
    putStrLn $ "   Programs executed: " ++ show cachedTotalExecutions
    putStrLn $ "   Patterns learned: " ++ show cachedPatternsAdded
    
    when (cachedEstimatedTimeSavedMs > 0) $
        putStrLn $ "   Estimated time saved: ~" ++ printf "%.1fms" cachedEstimatedTimeSavedMs


-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()