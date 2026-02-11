{-# LANGUAGE RecordWildCards #-}

module AdvancedPatternCacheTests
    ( runAdvancedPatternCacheTests
    , AdvancedCacheTestResult(..)
    ) where

import AdvancedPatternCache
import ProcessorTests (TestResult(..))
import ExecutionTracing (ProgramResult(..), TerminationType(..), ExecutionTrace(..), ExecutionState(..))
import PatternCache (CacheStatistics(..))
import Processor (Byte)
import Data.Time (getCurrentTime, UTCTime)
import Data.Map (Map)
import qualified Data.Map as Map
import System.Directory (removeFile, doesFileExist)

-- | Result of an advanced pattern cache test
data AdvancedCacheTestResult = AdvancedCacheTestResult
    { cacheTestName :: String
    , cacheTestPassed :: Bool
    , cacheExpectedResult :: String
    , cacheActualResult :: String
    , cacheErrorMessage :: Maybe String
    } deriving (Show)

-- | Convert AdvancedCacheTestResult to TestResult for integration
toTestResult :: AdvancedCacheTestResult -> TestResult
toTestResult AdvancedCacheTestResult{..} = TestResult
    { testName = cacheTestName
    , testPassed = cacheTestPassed
    , expectedResult = cacheExpectedResult
    , actualResult = cacheActualResult
    , errorMessage = cacheErrorMessage
    }

-- | Run all advanced pattern cache tests
runAdvancedPatternCacheTests :: IO [TestResult]
runAdvancedPatternCacheTests = do
    putStrLn "🧠 Running Advanced Pattern Cache Tests..."
    let allTests = concat
            [ cacheCreationTests
            , basicCacheOperationTests
            , patternAnalysisTests
            , similarityTests
            , persistenceTests
            , statisticsTests
            , edgeCaseTests
            ]
    
    results <- mapM runAdvancedCacheTest allTests
    let testResults = map toTestResult results
    
    putStrLn $ "  Completed " ++ show (length testResults) ++ " advanced cache tests"
    return testResults

-- | Run a single advanced cache test
runAdvancedCacheTest :: IO AdvancedCacheTestResult -> IO AdvancedCacheTestResult
runAdvancedCacheTest testAction = do
    result <- testAction
    putStrLn $ "    " ++ cacheTestName result ++ if cacheTestPassed result then " ✅" else " ❌"
    return result

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- | Create a sample program result for testing
createSampleProgramResult :: [Byte] -> Int -> TerminationType -> IO ProgramResult
createSampleProgramResult program outputLen termType = do
    timestamp <- getCurrentTime
    return ProgramResult
        { resultOutput = outputLen
        , resultSteps = 10
        , resultTermination = termType
        , resultTrace = ExecutionTrace [] 10 (ExecutionState 0 0 0 10 outputLen Nothing)
        , resultProgram = program
        , resultTimestamp = timestamp
        }

-- | Create a test that checks if two values are equal
testEqual :: (Eq a, Show a) => String -> a -> a -> AdvancedCacheTestResult
testEqual testName expected actual = AdvancedCacheTestResult
    { cacheTestName = testName
    , cacheTestPassed = expected == actual
    , cacheExpectedResult = show expected
    , cacheActualResult = show actual
    , cacheErrorMessage = if expected == actual then Nothing else Just "Values do not match"
    }

-- | Create a test that checks if a boolean condition is true
testCondition :: String -> Bool -> String -> String -> AdvancedCacheTestResult
testCondition testName condition expectedDesc actualDesc = AdvancedCacheTestResult
    { cacheTestName = testName
    , cacheTestPassed = condition
    , cacheExpectedResult = expectedDesc
    , cacheActualResult = actualDesc
    , cacheErrorMessage = if condition then Nothing else Just "Condition failed"
    }

-- =============================================================================
-- TEST CASES
-- =============================================================================

-- | Cache creation and initialization tests
cacheCreationTests :: [IO AdvancedCacheTestResult]
cacheCreationTests =
    [ testCacheCreation
    , testEmptyCacheStatistics
    ]

-- Test cache creation
testCacheCreation :: IO AdvancedCacheTestResult
testCacheCreation = do
    cache <- createAdvancedCache
    let entriesEmpty = Map.null (cacheEntries cache)
        versionCorrect = cacheVersion cache == "3.0"
        statsValid = totalPatterns (statistics cache) == 0
    
    return $ testCondition
        "Cache Creation"
        (entriesEmpty && versionCorrect && statsValid)
        "Empty cache with version 3.0 and zero statistics"
        ("Entries empty: " ++ show entriesEmpty ++ ", Version: " ++ cacheVersion cache ++ 
         ", Total patterns: " ++ show (totalPatterns (statistics cache)))

-- Test empty cache statistics
testEmptyCacheStatistics :: IO AdvancedCacheTestResult
testEmptyCacheStatistics = do
    cache <- createAdvancedCache
    let stats = statistics cache
        allZero = cacheHits stats == 0 && cacheMisses stats == 0 && totalPatterns stats == 0
    
    return $ testCondition
        "Empty Cache Statistics"
        allZero
        "All statistics should be zero"
        ("Hits: " ++ show (cacheHits stats) ++ ", Misses: " ++ show (cacheMisses stats) ++ 
         ", Patterns: " ++ show (totalPatterns stats))

-- | Basic cache operation tests
basicCacheOperationTests :: [IO AdvancedCacheTestResult]
basicCacheOperationTests =
    [ testCacheMiss
    , testCacheHit
    , testCacheAddAndLookup
    ]

-- Test cache miss on empty cache
testCacheMiss :: IO AdvancedCacheTestResult
testCacheMiss = do
    cache <- createAdvancedCache
    let program = [8, 15, 0]  -- PRINT 15, HALT
    (result, updatedCache) <- lookupByPattern program cache
    
    let missOccurred = result == Nothing
        missesIncremented = cacheMisses (statistics updatedCache) == 1
        hitsStayZero = cacheHits (statistics updatedCache) == 0
    
    return $ testCondition
        "Cache Miss on Empty Cache"
        (missOccurred && missesIncremented && hitsStayZero)
        "Should return Nothing and increment miss counter"
        ("Result: " ++ show (case result of Nothing -> "Miss"; Just _ -> "Hit") ++ 
         ", Misses: " ++ show (cacheMisses (statistics updatedCache)) ++
         ", Hits: " ++ show (cacheHits (statistics updatedCache)))

-- Test cache hit after adding entry
testCacheHit :: IO AdvancedCacheTestResult
testCacheHit = do
    cache <- createAdvancedCache
    let program = [8, 15, 0]
    
    -- Add program to cache
    programResult <- createSampleProgramResult program 2 Halt
    cacheWithEntry <- addPatternAnalysis program programResult cache
    
    -- Look up the same program
    (result, finalCache) <- lookupByPattern program cacheWithEntry
    
    let hitOccurred = case result of Just _ -> True; Nothing -> False
        hitsIncremented = cacheHits (statistics finalCache) > cacheHits (statistics cacheWithEntry)
    
    return $ testCondition
        "Cache Hit After Adding Entry"
        (hitOccurred && hitsIncremented)
        "Should return cached result and increment hit counter"
        ("Result: " ++ show (case result of Nothing -> "Miss"; Just _ -> "Hit") ++ 
         ", Hits: " ++ show (cacheHits (statistics finalCache)))

-- Test adding to cache and immediate lookup
testCacheAddAndLookup :: IO AdvancedCacheTestResult
testCacheAddAndLookup = do
    cache <- createAdvancedCache
    let program = [8, 10, 13, 0]  -- PRINT 10, JMP 0
    
    programResult <- createSampleProgramResult program 2 Halt
    cacheWithEntry <- addPatternAnalysis program programResult cache
    (lookupResult, _) <- lookupByPattern program cacheWithEntry
    
    let foundResult = case lookupResult of 
            Just result -> resultOutput result == 2 && resultProgram result == program
            Nothing -> False
        entryCount = Map.size (cacheEntries cacheWithEntry)
    
    return $ testCondition
        "Cache Add and Lookup"
        (foundResult && entryCount == 1)
        "Should find added program with correct output"
        ("Found: " ++ show foundResult ++ ", Entry count: " ++ show entryCount)

-- | Pattern analysis tests
patternAnalysisTests :: [IO AdvancedCacheTestResult]
patternAnalysisTests =
    [ testPatternAnalysisAdding
    , testMultipleProgramAnalysis
    , testDifferentTerminationTypes
    ]

-- Test pattern analysis when adding programs
testPatternAnalysisAdding :: IO AdvancedCacheTestResult
testPatternAnalysisAdding = do
    cache <- createAdvancedCache
    let program = [8, 15, 0]
    
    programResult <- createSampleProgramResult program 2 Halt
    updatedCache <- addPatternAnalysis program programResult cache
    
    let patternsIncremented = totalPatterns (statistics updatedCache) == 1
        entryAdded = Map.size (cacheEntries updatedCache) == 1
        totalExecutionsIncremented = totalExecutions (statistics updatedCache) == 1
    
    return $ testCondition
        "Pattern Analysis Adding"
        (patternsIncremented && entryAdded && totalExecutionsIncremented)
        "Should increment pattern count, add entry, and increment executions"
        ("Patterns: " ++ show (totalPatterns (statistics updatedCache)) ++
         ", Entries: " ++ show (Map.size (cacheEntries updatedCache)) ++
         ", Executions: " ++ show (totalExecutions (statistics updatedCache)))

-- Test adding multiple programs
testMultipleProgramAnalysis :: IO AdvancedCacheTestResult
testMultipleProgramAnalysis = do
    cache <- createAdvancedCache
    let program1 = [8, 15, 0]
        program2 = [8, 10, 0]
        program3 = [13, 0]  -- JMP 0 (infinite loop)
    
    result1 <- createSampleProgramResult program1 2 Halt
    result2 <- createSampleProgramResult program2 2 Halt
    result3 <- createSampleProgramResult program3 0 InfiniteLoop
    
    cache1 <- addPatternAnalysis program1 result1 cache
    cache2 <- addPatternAnalysis program2 result2 cache1
    cache3 <- addPatternAnalysis program3 result3 cache2
    
    let totalPatterns' = totalPatterns (statistics cache3) == 3
        totalEntries = Map.size (cacheEntries cache3) == 3
        totalExecutions' = totalExecutions (statistics cache3) == 3
    
    return $ testCondition
        "Multiple Program Analysis"
        (totalPatterns' && totalEntries && totalExecutions')
        "Should handle multiple different programs correctly"
        ("Patterns: " ++ show (totalPatterns (statistics cache3)) ++
         ", Entries: " ++ show totalEntries ++
         ", Executions: " ++ show (totalExecutions (statistics cache3)))

-- Test different termination types
testDifferentTerminationTypes :: IO AdvancedCacheTestResult
testDifferentTerminationTypes = do
    cache <- createAdvancedCache
    let haltProgram = [8, 15, 0]        -- PRINT 15, HALT
        loopProgram = [13, 0]           -- JMP 0 (infinite loop)
        timeoutProgram = [1, 1, 1, 1]   -- Simulated timeout
    
    haltResult <- createSampleProgramResult haltProgram 2 Halt
    loopResult <- createSampleProgramResult loopProgram 0 InfiniteLoop
    timeoutResult <- createSampleProgramResult timeoutProgram 0 Timeout
    
    cache1 <- addPatternAnalysis haltProgram haltResult cache
    cache2 <- addPatternAnalysis loopProgram loopResult cache1
    cache3 <- addPatternAnalysis timeoutProgram timeoutResult cache2
    
    -- Test lookups
    (haltLookup, _) <- lookupByPattern haltProgram cache3
    (loopLookup, _) <- lookupByPattern loopProgram cache3
    (timeoutLookup, _) <- lookupByPattern timeoutProgram cache3
    
    let allFound = case (haltLookup, loopLookup, timeoutLookup) of
            (Just h, Just l, Just t) -> 
                resultOutput h == 2 && 
                resultOutput l == 0 && 
                resultOutput t == 0
            _ -> False
    
    return $ testCondition
        "Different Termination Types"
        allFound
        "Should handle Halt, InfiniteLoop, and Timeout correctly"
        ("Halt found: " ++ show (case haltLookup of Just _ -> True; Nothing -> False) ++
         ", Loop found: " ++ show (case loopLookup of Just _ -> True; Nothing -> False) ++
         ", Timeout found: " ++ show (case timeoutLookup of Just _ -> True; Nothing -> False))

-- | Similarity tests
similarityTests :: [IO AdvancedCacheTestResult]
similarityTests =
    [ testSimilarProgramDetection
    , testNoSimilarPrograms
    ]

-- Test similar program detection
testSimilarProgramDetection :: IO AdvancedCacheTestResult
testSimilarProgramDetection = do
    cache <- createAdvancedCache
    let program1 = [8, 15, 0]
        program2 = [8, 15, 0]  -- Identical program
    
    result1 <- createSampleProgramResult program1 2 Halt
    cacheWithEntry <- addPatternAnalysis program1 result1 cache
    
    similarPrograms <- findSimilarPrograms program2 cacheWithEntry
    
    let foundSimilar = not (null similarPrograms)
        correctProgram = case similarPrograms of
            (entry:_) -> entryProgram entry == program1
            [] -> False
    
    return $ testCondition
        "Similar Program Detection"
        (foundSimilar && correctProgram)
        "Should find identical program as similar"
        ("Found similar: " ++ show foundSimilar ++ ", Correct program: " ++ show correctProgram)

-- Test no similar programs
testNoSimilarPrograms :: IO AdvancedCacheTestResult
testNoSimilarPrograms = do
    cache <- createAdvancedCache
    let program1 = [8, 15, 0]
        program2 = [13, 5, 0]  -- Completely different program
    
    result1 <- createSampleProgramResult program1 2 Halt
    cacheWithEntry <- addPatternAnalysis program1 result1 cache
    
    similarPrograms <- findSimilarPrograms program2 cacheWithEntry
    
    let noSimilarFound = null similarPrograms
    
    return $ testCondition
        "No Similar Programs"
        noSimilarFound
        "Should find no similar programs for different program"
        ("Similar programs found: " ++ show (length similarPrograms))

-- | Persistence tests
persistenceTests :: [IO AdvancedCacheTestResult]
persistenceTests =
    [ testCacheSaveAndLoad
    , testCacheLoadNonexistent
    , testCachePersistencePreservesData
    ]

-- Test cache save and load
testCacheSaveAndLoad :: IO AdvancedCacheTestResult
testCacheSaveAndLoad = do
    -- Create and populate cache
    cache <- createAdvancedCache
    let program = [8, 15, 0]
        tempFile = "/tmp/test_cache_" ++ show program ++ ".json"
    programResult <- createSampleProgramResult program 2 Halt
    populatedCache <- addPatternAnalysis program programResult cache
    
    -- Save cache
    saveAdvancedCache tempFile populatedCache
    
    -- Load cache
    loadedCache <- loadAdvancedCache tempFile
    
    -- Clean up
    exists <- doesFileExist tempFile
    if exists then removeFile tempFile else return ()
    
    -- Compare
    let entriesMatch = Map.size (cacheEntries loadedCache) == Map.size (cacheEntries populatedCache)
        versionMatch = cacheVersion loadedCache == cacheVersion populatedCache
        statsMatch = totalPatterns (statistics loadedCache) > 0
    
    return $ testCondition
        "Cache Save and Load"
        (entriesMatch && versionMatch && statsMatch)
        "Should preserve cache data through save/load cycle"
        ("Entries match: " ++ show entriesMatch ++ ", Version match: " ++ show versionMatch ++ 
         ", Stats preserved: " ++ show statsMatch)

-- Test loading nonexistent cache
testCacheLoadNonexistent :: IO AdvancedCacheTestResult
testCacheLoadNonexistent = do
    let nonexistentFile = "/tmp/definitely_does_not_exist_cache.json"
    loadedCache <- loadAdvancedCache nonexistentFile
    
    let isEmpty = Map.null (cacheEntries loadedCache)
        correctVersion = cacheVersion loadedCache == "3.0"
        zeroStats = totalPatterns (statistics loadedCache) == 0
    
    return $ testCondition
        "Load Nonexistent Cache"
        (isEmpty && correctVersion && zeroStats)
        "Should create empty cache when file doesn't exist"
        ("Empty: " ++ show isEmpty ++ ", Version: " ++ cacheVersion loadedCache ++ 
         ", Zero stats: " ++ show zeroStats)

-- Test persistence preserves program data
testCachePersistencePreservesData :: IO AdvancedCacheTestResult
testCachePersistencePreservesData = do
    cache <- createAdvancedCache
    let program = [8, 10, 13, 2]
        tempFile = "/tmp/test_persist_" ++ show program ++ ".json"
    
    programResult <- createSampleProgramResult program 2 Halt
    populatedCache <- addPatternAnalysis program programResult cache
    
    -- Save and reload
    saveAdvancedCache tempFile populatedCache
    loadedCache <- loadAdvancedCache tempFile
    
    -- Clean up
    exists <- doesFileExist tempFile
    if exists then removeFile tempFile else return ()
    
    -- Test lookup on loaded cache
    (lookupResult, _) <- lookupByPattern program loadedCache
    
    let dataPreserved = case lookupResult of
            Just result -> resultOutput result == 2 && resultProgram result == program
            Nothing -> False
    
    return $ testCondition
        "Cache Persistence Preserves Data"
        dataPreserved
        "Should preserve program data through save/load cycle"
        ("Data preserved: " ++ show dataPreserved)

-- | Statistics tests
statisticsTests :: [IO AdvancedCacheTestResult]
statisticsTests =
    [ testStatisticsUpdating
    , testHitRateCalculation
    ]

-- Test statistics updating
testStatisticsUpdating :: IO AdvancedCacheTestResult
testStatisticsUpdating = do
    cache <- createAdvancedCache
    let program1 = [8, 15, 0]
        program2 = [8, 10, 0]
    
    -- Add first program
    result1 <- createSampleProgramResult program1 2 Halt
    cache1 <- addPatternAnalysis program1 result1 cache
    
    -- Look up (miss)
    (_, cache2) <- lookupByPattern program2 cache1
    
    -- Look up first program (hit)
    (_, cache3) <- lookupByPattern program1 cache2
    
    let stats = statistics cache3
        correctStats = totalPatterns stats == 1 && 
                      cacheMisses stats == 1 && 
                      cacheHits stats >= 1 &&
                      totalExecutions stats == 1
    
    return $ testCondition
        "Statistics Updating"
        correctStats
        "Should correctly update all statistics"
        ("Patterns: " ++ show (totalPatterns stats) ++
         ", Hits: " ++ show (cacheHits stats) ++
         ", Misses: " ++ show (cacheMisses stats) ++
         ", Executions: " ++ show (totalExecutions stats))

-- Test hit rate calculation
testHitRateCalculation :: IO AdvancedCacheTestResult
testHitRateCalculation = do
    cache <- createAdvancedCache
    let program = [8, 15, 0]
    
    result <- createSampleProgramResult program 2 Halt
    cache1 <- addPatternAnalysis program result cache
    
    -- Hit
    (_, cache2) <- lookupByPattern program cache1
    -- Hit again
    (_, cache3) <- lookupByPattern program cache2
    -- Miss
    (_, cache4) <- lookupByPattern [8, 10, 0] cache3
    
    let stats = statistics cache4
        hits = cacheHits stats
        misses = cacheMisses stats
        expectedHitRate = if hits + misses > 0 
                         then fromIntegral hits / fromIntegral (hits + misses) 
                         else 0.0
        hitRateReasonable = expectedHitRate > 0.0 && expectedHitRate <= 1.0
    
    return $ testCondition
        "Hit Rate Calculation"
        hitRateReasonable
        "Should maintain reasonable hit rate statistics"
        ("Hits: " ++ show hits ++ ", Misses: " ++ show misses ++ 
         ", Rate: " ++ show expectedHitRate)

-- | Edge case tests
edgeCaseTests :: [IO AdvancedCacheTestResult]
edgeCaseTests =
    [ testEmptyProgram
    , testLargeProgram
    , testDuplicateAddition
    ]

-- Test empty program
testEmptyProgram :: IO AdvancedCacheTestResult
testEmptyProgram = do
    cache <- createAdvancedCache
    let emptyProgram = []
    
    result <- createSampleProgramResult emptyProgram 0 Halt
    updatedCache <- addPatternAnalysis emptyProgram result cache
    (lookupResult, _) <- lookupByPattern emptyProgram updatedCache
    
    let handledCorrectly = case lookupResult of
            Just r -> resultOutput r == 0 && resultProgram r == []
            Nothing -> False
    
    return $ testCondition
        "Empty Program"
        handledCorrectly
        "Should handle empty program correctly"
        ("Handled correctly: " ++ show handledCorrectly)

-- Test large program
testLargeProgram :: IO AdvancedCacheTestResult
testLargeProgram = do
    cache <- createAdvancedCache
    let largeProgram = [8, 15, 8, 14, 8, 13, 8, 12, 8, 11, 8, 10, 13, 0, 0, 0]  -- 16 bytes
    
    result <- createSampleProgramResult largeProgram 12 Halt  -- 6 PRINT operations
    updatedCache <- addPatternAnalysis largeProgram result cache
    (lookupResult, _) <- lookupByPattern largeProgram updatedCache
    
    let handledCorrectly = case lookupResult of
            Just r -> resultOutput r == 12 && length (resultProgram r) == 16
            Nothing -> False
    
    return $ testCondition
        "Large Program"
        handledCorrectly
        "Should handle 16-byte program correctly"
        ("Handled correctly: " ++ show handledCorrectly)

-- Test duplicate addition
testDuplicateAddition :: IO AdvancedCacheTestResult
testDuplicateAddition = do
    cache <- createAdvancedCache
    let program = [8, 15, 0]
    
    result1 <- createSampleProgramResult program 2 Halt
    result2 <- createSampleProgramResult program 2 Halt
    
    cache1 <- addPatternAnalysis program result1 cache
    cache2 <- addPatternAnalysis program result2 cache1  -- Add same program again
    
    let entryCount = Map.size (cacheEntries cache2)
        statsCorrect = totalPatterns (statistics cache2) == 2  -- Both additions counted
    
    return $ testCondition
        "Duplicate Addition"
        (entryCount == 1 && statsCorrect)  -- Should overwrite, not duplicate
        "Should handle duplicate program addition correctly"
        ("Entry count: " ++ show entryCount ++ ", Stats correct: " ++ show statsCorrect)