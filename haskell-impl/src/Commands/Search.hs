{-# LANGUAGE RecordWildCards #-}

module Commands.Search
    ( runSearchCommand
    ) where

import BruteForceSearch
import InstructionAnalysis (analyzeProgram)
import Text.Printf
import Data.Word (Word8)
import System.IO.Error (tryIOError)
import System.Directory (removeFile, doesFileExist)

-- | Run the search command
runSearchCommand :: Int -> Bool -> Bool -> Bool -> String -> Bool -> IO ()
runSearchCommand searchLength useCached useAdvanced fresh cacheFile verbose = do
    when verbose $ putStrLn $ "Searching for optimal programs of length " ++ show searchLength
    
    -- Handle fresh cache option
    when (useCached && fresh) $ do
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
        if useCached
            then putStrLn $ "Using cache file: " ++ cacheFile
            else putStrLn "Caching disabled"
        when useAdvanced $ putStrLn "Using Phase 2 advanced pattern analysis"
    
    putStrLn $ "=== Program Search (Length " ++ show searchLength ++ ") ==="
    putStrLn $ "Searching " ++ show (16^searchLength) ++ " possible programs..."
    putStrLn ""
    
    (result, maybeCachedResult) <- if useAdvanced
              then do
                  when verbose $ putStrLn "Using Phase 2 advanced pattern analysis..."
                  cachedResult <- findLongestOutputProgramAdvanced cacheFile searchLength
                  return (convertCachedResult cachedResult, Just cachedResult)
              else if useCached 
              then do
                  when verbose $ putStrLn "Using persistent memoization cache..."
                  cachedResult <- findLongestOutputProgramCachedWithFile cacheFile searchLength
                  return (convertCachedResult cachedResult, Just cachedResult)
              else do
                  when verbose $ putStrLn "Running direct search..."
                  directResult <- findLongestOutputProgramTimed searchLength
                  return (directResult, Nothing)
    
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
    
    -- Display cache statistics if using advanced caching
    when (useCached && useAdvanced) $ do
        putStrLn ""
        case maybeCachedResult of
            Just cachedResult -> displayCacheStatistics cachedResult
            Nothing -> return ()
    
    when useCached $ do
        putStrLn ""
        putStrLn $ "💾 Cache file '" ++ cacheFile ++ "' updated."
        putStrLn "🔄 Run again to benefit from cached results!"

-- | Convert cached search result to standard search result
convertCachedResult :: CachedSearchResult -> SearchResult
convertCachedResult cached = SearchResult
    { bestProgram = cachedBestProgram cached
    , searchTimeMs = cachedSearchTimeMs cached
    , programsTested = cachedProgramsTested cached
    , programsWithOutput = cachedProgramsWithOutput cached
    }

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