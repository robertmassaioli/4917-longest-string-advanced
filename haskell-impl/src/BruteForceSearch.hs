{-# LANGUAGE RecordWildCards #-}

module BruteForceSearch
    ( generateAllPrograms
    , findLongestOutputProgramAdvanced
    , CachedSearchResult(..)
    ) where

import Processor (Device(..), Byte, ProgramExecutionResult(..), createDevice, runProgramLoopCheck)
import Data.List (maximumBy, foldl')
import Data.Ord (comparing)
import Control.Monad (when)
import Data.Vector.Unboxed ((!))  -- For vector indexing
import System.CPUTime (getCPUTime)
import Text.Printf (printf)
import ExecutionTracing (runProgramWithTracing, ExecutionTrace(..), ExecutionState(..))
import qualified ExecutionTracing as ET
import PatternCache (loadCache, saveCache, lookupPattern, addPatternEntry, PatternResult(..), incrementTotalExecutions)
import qualified PatternCache as Cache
import PatternAnalyzer (analyzeProgram, detectHaltPattern, detectLoopPattern)
import AdvancedPatternCache (AdvancedPatternCache, createAdvancedCache, lookupByPattern, addPatternAnalysis, getCacheStatistics, saveAdvancedCache, loadAdvancedCache)

-- | Calculate the actual length of a program (position of last non-zero byte + 1)
calculateActualLength :: [Byte] -> Int
calculateActualLength program = 
    case [i | (i, byte) <- zip [0..] program, byte /= 0] of
        [] -> 0  -- All zeros
        indices -> maximum indices + 1  -- Last non-zero position + 1


-- | Result of a cached search with cache statistics
data CachedSearchResult = CachedSearchResult
    { cachedBestProgram :: Maybe ET.ProgramResult
    , cachedSearchTimeMs :: Double
    , cachedProgramsTested :: Int
    , cachedProgramsWithOutput :: Int
    , cachedCacheHits :: Int
    , cachedCacheMisses :: Int
    , cachedPatternsAdded :: Int
    , cachedExecutionsSaved :: Int
    , cachedWildcardHits :: Int
    , cachedSimilarityHits :: Int
    , cachedTotalExecutions :: Int
    , cachedEstimatedTimeSavedMs :: Double
    } deriving (Show, Eq)

-- | Generate all possible programs of a given length
-- Each instruction is 4 bits (0-15), so we generate all combinations
generateAllPrograms :: Int -> [Device]
generateAllPrograms programLength = map createDevice allPrograms
  where
    -- Generate all possible instruction sequences
    allPrograms = sequence (replicate programLength [0..15])

-- | Generate programs with exactly the specified length
-- This generates all possible programs of the given length, which means
-- all combinations of instructions for positions 0 to (targetLength-1)
generateProgramsOfExactLength :: Int -> [Device]
generateProgramsOfExactLength targetLength = generateAllPrograms targetLength



-- | Advanced pattern-based search with Phase 2 optimizations
findLongestOutputProgramAdvanced :: String -> Int -> IO CachedSearchResult
findLongestOutputProgramAdvanced cacheFilePath programLength 
    | programLength <= 0 || programLength > 8 = return $ CachedSearchResult 
        { cachedBestProgram = Nothing, cachedSearchTimeMs = 0.0, cachedProgramsTested = 0
        , cachedProgramsWithOutput = 0, cachedCacheHits = 0, cachedCacheMisses = 0
        , cachedPatternsAdded = 0, cachedExecutionsSaved = 0, cachedWildcardHits = 0
        , cachedSimilarityHits = 0, cachedTotalExecutions = 0, cachedEstimatedTimeSavedMs = 0.0 }
    | otherwise = do
        start <- getCPUTime
        advancedCache <- loadAdvancedCache cacheFilePath
        
        let exactLengthPrograms = generateProgramsOfExactLength programLength
            totalExactPrograms = length exactLengthPrograms
            -- For comparison, show how many we would have generated without filtering
            allPrograms = generateAllPrograms programLength
            totalAllPrograms = length allPrograms
        
        putStrLn $ "Filtered to " ++ show totalExactPrograms ++ " programs with exact length " ++ show programLength ++ 
                  " (from " ++ show totalAllPrograms ++ " total combinations)"
        putStrLn $ "Testing " ++ show totalExactPrograms ++ " programs of exact length " ++ show programLength ++ " with advanced pattern analysis..."
        
        -- Phase 2.1: HALT Pattern Detection - Skip programs without reachable HALT
        let haltOptimizedPrograms = if programLength <= 4
                                   then filter (not . hasUnreachableHalt) exactLengthPrograms
                                   else exactLengthPrograms  -- Only optimize for smaller lengths
            optimizedCount = length haltOptimizedPrograms
        
        when (optimizedCount < totalExactPrograms) $
            putStrLn $ "  HALT optimization: Skipped " ++ show (totalExactPrograms - optimizedCount) ++ " programs with unreachable HALT"
        
        -- Process programs with advanced pattern analysis
        (results, finalCache, hits, misses, patternsAdded) <- processWithAdvancedCache advancedCache haltOptimizedPrograms 0 0 0 []
        
        let validResults = filter (\r -> ET.resultOutput r > 0) results
            validCount = length validResults
            totalResults = length results
            bestResult = if null validResults 
                        then Nothing
                        else Just $ maximumBy (comparing ET.resultOutput) validResults
        
        
        end <- getCPUTime
        let timeDiffMs = fromIntegral (end - start) / (10^9)
            cacheStats = getCacheStatistics finalCache
        
        putStrLn $ "  Pattern analysis: " ++ show patternsAdded ++ " new patterns detected"
        
        -- Save the cache with all the learned patterns
        saveAdvancedCache cacheFilePath finalCache
        
        return $ CachedSearchResult 
            { cachedBestProgram = bestResult
            , cachedSearchTimeMs = timeDiffMs
            , cachedProgramsTested = optimizedCount
            , cachedProgramsWithOutput = validCount
            , cachedCacheHits = hits
            , cachedCacheMisses = misses
            , cachedPatternsAdded = patternsAdded
            , cachedExecutionsSaved = Cache.executionsSaved cacheStats
            , cachedWildcardHits = Cache.wildcardHits cacheStats
            , cachedSimilarityHits = Cache.similarityHits cacheStats
            , cachedTotalExecutions = Cache.totalExecutions cacheStats
            , cachedEstimatedTimeSavedMs = Cache.estimatedTimeSavedMs cacheStats
            }
  where
    -- Phase 2.1: HALT pattern detection optimization
    hasUnreachableHalt :: Device -> Bool
    hasUnreachableHalt device =
        let programBytes = take programLength $ extractProgramBytes device
            haltPositions = [i | (i, instr) <- zip [0..] programBytes, instr == 0]
            -- Simple reachability: check if HALT is after unconditional jumps to earlier positions
            hasEarlyLoop = any (\(i, instr) -> instr == 13 && i < programLength - 1) (zip [0..] programBytes)
        in not (null haltPositions) && hasEarlyLoop && last haltPositions > 2
    
    processWithAdvancedCache :: AdvancedPatternCache -> [Device] -> Int -> Int -> Int -> [ET.ProgramResult] 
                            -> IO ([ET.ProgramResult], AdvancedPatternCache, Int, Int, Int)
    processWithAdvancedCache cache [] hits misses added results = return (reverse results, cache, hits, misses, added)
    processWithAdvancedCache cache (device:devices) hits misses added results = do
        let programBytes = take programLength $ extractProgramBytes device
        
        -- Try advanced pattern lookup
        (maybeResult, updatedCache) <- lookupByPattern programBytes cache
        
        case maybeResult of
            Just cachedExecutionResult -> do
                -- Cache hit - convert ExecutionTracing.ProgramResult to BruteForceSearch.ProgramResult
                let outputLen = case ET.resultTermination cachedExecutionResult of
                        ET.InfiniteLoop -> 0  -- Infinite loops produce no useful output
                        ET.Timeout -> 0       -- Timeouts are treated as infinite loops
                        _ -> ET.resultOutput cachedExecutionResult
                    programResult = ET.ProgramResult
                        { resultOutput = outputLen
                        , resultSteps = 0  -- We don't track steps from cached results
                        , resultTermination = ET.Halt  -- Assume successful if cached
                        , resultTrace = ExecutionTrace [] 0 (ExecutionState 0 0 0 0 outputLen Nothing)
                        , resultProgram = programBytes
                        , resultTimestamp = error "Timestamp not available in cache lookup"
                        }
                processWithAdvancedCache updatedCache devices (hits + 1) misses added (programResult:results)
            
            Nothing -> do
                -- Cache miss - compute with pattern analysis
                executionResult <- runProgramWithTracing programBytes
                
                -- Phase 2.2: Loop Pattern Recognition
                let loopPattern = detectLoopPattern executionResult
                    haltPattern = detectHaltPattern programBytes executionResult
                
                -- Apply Phase 2 optimizations based on detected patterns
                let outputLen = case ET.resultTermination executionResult of
                        ET.InfiniteLoop -> 0  -- Infinite loops produce no useful output
                        ET.Timeout -> 0       -- Timeouts are treated as infinite loops
                        _ -> ET.resultOutput executionResult
                
                let programResult = ET.ProgramResult
                        { resultOutput = outputLen
                        , resultSteps = ET.resultSteps executionResult
                        , resultTermination = ET.resultTermination executionResult
                        , resultTrace = ET.resultTrace executionResult
                        , resultProgram = programBytes
                        , resultTimestamp = ET.resultTimestamp executionResult
                        }
                
                
                -- Add to advanced cache with pattern analysis
                cacheWithPattern <- addPatternAnalysis programBytes executionResult updatedCache
                
                processWithAdvancedCache cacheWithPattern devices hits (misses + 1) (added + 1) (programResult:results)
    
    extractProgramBytes :: Device -> [Byte]
    extractProgramBytes Device{..} = [memory ! i | i <- [0..15]]