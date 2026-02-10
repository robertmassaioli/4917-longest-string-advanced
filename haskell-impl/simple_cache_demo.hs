import BruteForceSearch (findLongestOutputProgramCached, cachedBestProgram, cachedSearchTimeMs, cachedCacheHits, cachedCacheMisses, cachedPatternsAdded, programBytes, outputLength)
import Text.Printf

main = do
    putStrLn "=== Simple Persistent Memoization Demo ==="
    putStrLn "Testing Length 3 programs (4,096 programs) with caching...\n"
    
    putStrLn "📝 First run (building cache):"
    result1 <- findLongestOutputProgramCached 3
    
    case cachedBestProgram result1 of
        Nothing -> putStrLn "❌ No programs found"
        Just prog -> do
            putStrLn $ "✅ Found: " ++ show (programBytes prog) ++ " → " ++ show (outputLength prog) ++ " chars"
            putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result1)
            putStrLn $ "   Cache: " ++ show (cachedCacheHits result1) ++ " hits, " ++ show (cachedCacheMisses result1) ++ " misses"
            putStrLn $ "   Added: " ++ show (cachedPatternsAdded result1) ++ " patterns"
    
    putStrLn "\n🚀 Second run (using cache):"
    result2 <- findLongestOutputProgramCached 3
    
    case cachedBestProgram result2 of
        Nothing -> putStrLn "❌ No programs found"
        Just prog -> do
            putStrLn $ "✅ Found: " ++ show (programBytes prog) ++ " → " ++ show (outputLength prog) ++ " chars"  
            putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result2)
            putStrLn $ "   Cache: " ++ show (cachedCacheHits result2) ++ " hits, " ++ show (cachedCacheMisses result2) ++ " misses"
            putStrLn $ "   Added: " ++ show (cachedPatternsAdded result2) ++ " patterns"
    
    let speedup = if cachedSearchTimeMs result2 > 0 
                 then cachedSearchTimeMs result1 / cachedSearchTimeMs result2 
                 else 1.0
    putStrLn $ "\n⚡ Speedup: " ++ printf "%.1fx" speedup
    putStrLn "💾 Cache saved to 'program_cache.json'"
