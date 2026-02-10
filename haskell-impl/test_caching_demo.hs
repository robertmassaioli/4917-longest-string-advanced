#!/usr/bin/env stack
{- stack script --resolver lts-22.28 
   --package base 
   --package vector 
   --package time
   --package deepseq
   --package aeson
   --package containers
   --ghc-options -threaded
-}

import BruteForceSearch
import Text.Printf
import System.CPUTime

-- | Demo of persistent memoization caching system
main :: IO ()
main = do
    putStrLn "=== Persistent Memoization Demo ==="
    putStrLn "This demo shows how the caching system works across multiple runs.\n"
    
    -- Test Length 4 multiple times to show caching benefits
    putStrLn "🧪 Testing Length 4 programs (65,536 programs):"
    putStrLn "First run will populate cache, subsequent runs should be faster.\n"
    
    -- First run (cache building)
    putStrLn "📝 Run 1: Building cache..."
    start1 <- getCPUTime
    result1 <- findLongestOutputProgramCached 4
    end1 <- getCPUTime
    let time1 = fromIntegral (end1 - start1) / (10^9) :: Double
    
    case cachedBestProgram result1 of
        Nothing -> putStrLn "❌ No programs found"
        Just prog -> do
            putStrLn $ "✅ Best program: " ++ show (programBytes prog)
            putStrLn $ "   Output length: " ++ show (outputLength prog) ++ " characters"
            putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result1)
            putStrLn $ "   Cache: " ++ show (cachedCacheHits result1) ++ " hits, " ++ 
                      show (cachedCacheMisses result1) ++ " misses"
            putStrLn $ "   New patterns: " ++ show (cachedPatternsAdded result1)
    
    putStrLn ""
    
    -- Second run (cache usage)
    putStrLn "🚀 Run 2: Using existing cache..."
    start2 <- getCPUTime  
    result2 <- findLongestOutputProgramCached 4
    end2 <- getCPUTime
    let time2 = fromIntegral (end2 - start2) / (10^9) :: Double
    
    case cachedBestProgram result2 of
        Nothing -> putStrLn "❌ No programs found"
        Just prog -> do
            putStrLn $ "✅ Best program: " ++ show (programBytes prog)
            putStrLn $ "   Output length: " ++ show (outputLength prog) ++ " characters"
            putStrLn $ "   Time: " ++ printf "%.1fms" (cachedSearchTimeMs result2)
            putStrLn $ "   Cache: " ++ show (cachedCacheHits result2) ++ " hits, " ++ 
                      show (cachedCacheMisses result2) ++ " misses"
            putStrLn $ "   New patterns: " ++ show (cachedPatternsAdded result2)
    
    putStrLn ""
    
    -- Performance analysis
    let hitRate1 = if cachedProgramsTested result1 > 0 
                  then fromIntegral (cachedCacheHits result1) / fromIntegral (cachedProgramsTested result1) * 100
                  else 0
        hitRate2 = if cachedProgramsTested result2 > 0
                  then fromIntegral (cachedCacheHits result2) / fromIntegral (cachedProgramsTested result2) * 100  
                  else 0
        speedup = if time2 > 0 then time1 / time2 else 1.0
    
    putStrLn "📊 Performance Analysis:"
    putStrLn $ "   Run 1 hit rate: " ++ printf "%.1f%%" hitRate1
    putStrLn $ "   Run 2 hit rate: " ++ printf "%.1f%%" hitRate2
    putStrLn $ "   Actual speedup: " ++ printf "%.1fx" speedup
    
    if speedup > 1.1 then
        putStrLn "✅ Caching provides measurable speedup!"
    else if speedup > 0.9 then
        putStrLn "⚖️  Similar performance (cache overhead ~= computation saved)"
    else  
        putStrLn "⚠️  Cache overhead currently dominates (expected for small problems)"
    
    putStrLn "\n💾 Cache file 'program_cache.json' has been created/updated."
    putStrLn "🔄 Run this demo again to see cumulative caching benefits!"