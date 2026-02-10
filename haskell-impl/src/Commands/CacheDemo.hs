module Commands.CacheDemo
    ( runCacheDemoCommand
    ) where

import BruteForceSearch
import qualified ExecutionTracing as ET
import Text.Printf
import System.CPUTime
import System.IO.Error (tryIOError)
import System.Directory (removeFile, doesFileExist)

-- | Run the cache demo command
runCacheDemoCommand :: Maybe Int -> Bool -> Bool -> String -> IO ()
runCacheDemoCommand maybeLength verbose fresh cacheFile = do
    let defaultLength = maybe 3 id maybeLength
    
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
        putStrLn $ "Running persistent memoization demo with length " ++ show defaultLength
    
    putStrLn "=== Persistent Memoization Demo ==="
    putStrLn "This demo shows how the caching system works across multiple runs.\\n"
    
    -- Test specified length multiple times to show caching benefits
    putStrLn $ "🧪 Testing Length " ++ show defaultLength ++ " programs (" ++ show (16^defaultLength) ++ " programs):"
    putStrLn "First run will populate cache, subsequent runs should be faster.\\n"
    
    -- First run (cache building)
    putStrLn "📝 Run 1: Building cache..."
    start1 <- getCPUTime
    result1 <- findLongestOutputProgramAdvanced cacheFile defaultLength
    end1 <- getCPUTime
    let time1 = fromIntegral (end1 - start1) / (10^9) :: Double
    
    case cachedBestProgram result1 of
        Nothing -> putStrLn "❌ No programs found"
        Just prog -> do
            putStrLn $ "✅ Best program: " ++ show (ET.resultProgram prog)
            putStrLn $ "   Output length: " ++ show (ET.resultOutput prog) ++ " characters"
            putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result1)
            putStrLn $ "   Cache: " ++ show (cachedCacheHits result1) ++ " hits, " ++ 
                      show (cachedCacheMisses result1) ++ " misses"
            putStrLn $ "   New patterns: " ++ show (cachedPatternsAdded result1)
    
    putStrLn ""
    
    -- Second run (cache usage)
    putStrLn "🚀 Run 2: Using existing cache..."
    start2 <- getCPUTime  
    result2 <- findLongestOutputProgramAdvanced cacheFile defaultLength
    end2 <- getCPUTime
    let time2 = fromIntegral (end2 - start2) / (10^9) :: Double
    
    case cachedBestProgram result2 of
        Nothing -> putStrLn "❌ No programs found"
        Just prog -> do
            putStrLn $ "✅ Best program: " ++ show (ET.resultProgram prog)
            putStrLn $ "   Output length: " ++ show (ET.resultOutput prog) ++ " characters"
            putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result2)
            putStrLn $ "   Cache: " ++ show (cachedCacheHits result2) ++ " hits, " ++ 
                      show (cachedCacheMisses result2) ++ " misses"
            putStrLn $ "   New patterns: " ++ show (cachedPatternsAdded result2)
    
    putStrLn ""
    
    -- Performance analysis
    let hitRate1 = if cachedProgramsTested result1 > 0 
                  then fromIntegral (cachedCacheHits result1) / fromIntegral (cachedProgramsTested result1) * 100
                  else 0 :: Double
        hitRate2 = if cachedProgramsTested result2 > 0
                  then fromIntegral (cachedCacheHits result2) / fromIntegral (cachedProgramsTested result2) * 100  
                  else 0 :: Double
        speedup = if time2 > 0 then time1 / time2 else 1.0
        reportedSpeedup = if cachedSearchTimeMs result2 > 0 
                         then cachedSearchTimeMs result1 / cachedSearchTimeMs result2 
                         else 1.0
    
    putStrLn "📊 Performance Analysis:"
    putStrLn $ "   Run 1 hit rate: " ++ printf "%.1f%%" hitRate1
    putStrLn $ "   Run 2 hit rate: " ++ printf "%.1f%%" hitRate2
    putStrLn $ "   Reported speedup: " ++ printf "%.1fx" reportedSpeedup
    putStrLn $ "   Actual speedup: " ++ printf "%.1fx" speedup
    
    if reportedSpeedup > 1.5 then
        putStrLn "✅ Caching provides significant speedup!"
    else if reportedSpeedup > 1.1 then
        putStrLn "✅ Caching provides measurable speedup!"
    else if reportedSpeedup > 0.9 then
        putStrLn "⚖️  Similar performance (cache overhead ~= computation saved)"
    else  
        putStrLn "⚠️  Cache overhead currently dominates (expected for small problems)"
    
    putStrLn "\\n💡 Expected behavior:"
    putStrLn "   - Length 3: Modest benefits (small problem size)"
    putStrLn "   - Length 4-5: Better benefits (more computation to save)"
    putStrLn "   - Length 6+: Excellent benefits (exponential computation vs linear cache)"
    
    putStrLn $ "\\n💾 Cache file '" ++ cacheFile ++ "' has been created/updated."
    putStrLn "🔄 Run this demo again to see cumulative caching benefits!"
    
    -- Test additional length if different from default
    when (defaultLength < 4) $ do
        putStrLn "\\n🧪 Quick test of Length 4 (65,536 programs):"
        result4 <- findLongestOutputProgramAdvanced cacheFile 4
        case cachedBestProgram result4 of
            Nothing -> putStrLn "❌ No programs found"
            Just prog -> do
                putStrLn $ "✅ Best: " ++ show (ET.resultProgram prog) ++ " → " ++ show (ET.resultOutput prog) ++ " chars"
                putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result4)
                putStrLn $ "   Cache: " ++ show (cachedCacheHits result4) ++ " hits, " ++ 
                          show (cachedCacheMisses result4) ++ " misses"

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()