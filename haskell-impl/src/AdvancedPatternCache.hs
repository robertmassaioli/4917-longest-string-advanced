{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module AdvancedPatternCache
    ( AdvancedPatternCache(..)
    , PatternEntry(..)
    , createAdvancedCache
    , lookupByPattern
    , addPatternAnalysis
    , findSimilarPrograms
    , getCacheStatistics
    , saveAdvancedCache
    , loadAdvancedCache
    ) where

import PatternAnalyzer
import qualified WildcardPatterns as WP
import ExecutionTracing (ProgramResult(..), TerminationType(..), ExecutionTrace(..), ExecutionState(..), extractExecutionSteps)
import PatternCache (ProgramCache(..), CacheStatistics(..), incrementExecutionsSaved, incrementWildcardHits, incrementSimilarityHits, addTimeSaved, incrementTotalExecutions)
import qualified PatternCache as Basic
import Processor (Byte)
import Data.Time (UTCTime, getCurrentTime)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.List (sortBy)
import Data.Aeson
import GHC.Generics (Generic)
import Control.DeepSeq (NFData, rnf)
import System.Directory (doesFileExist)
import System.IO.Error (tryIOError)

-- | Simplified pattern cache entry for basic persistence
data PatternEntry = PatternEntry
    { entryProgram :: [Byte]
    , entryOutputLength :: Int
    , entryCreatedAt :: UTCTime
    , entryLastUsed :: UTCTime
    , entryUseCount :: Int
    } deriving (Show, Eq, Generic, ToJSON, FromJSON)

instance NFData PatternEntry where
    rnf (PatternEntry prog output created used count) = 
        rnf prog `seq` rnf output `seq` rnf created `seq` rnf used `seq` rnf count

-- | Simplified advanced cache with basic persistence
data AdvancedPatternCache = AdvancedPatternCache
    { cacheEntries :: Map String PatternEntry      -- Keyed by program bytes
    , statistics :: CacheStatistics
    , cacheVersion :: String
    } deriving (Show, Eq, Generic, ToJSON, FromJSON)

instance NFData AdvancedPatternCache where
    rnf (AdvancedPatternCache entries stats ver) = 
        rnf entries `seq` rnf stats `seq` rnf ver

-- | Create empty advanced cache
createAdvancedCache :: IO AdvancedPatternCache
createAdvancedCache = do
    now <- getCurrentTime
    return AdvancedPatternCache
        { cacheEntries = Map.empty
        , statistics = CacheStatistics 0 0 0 now 0 0 0 0 0.0
        , cacheVersion = "3.0"
        }

-- | Look up a program by its pattern characteristics
lookupByPattern :: [Byte] -> AdvancedPatternCache -> IO (Maybe ProgramResult, AdvancedPatternCache)
lookupByPattern program cache = do
    let programKey = show program
    case Map.lookup programKey (cacheEntries cache) of
        Nothing -> do
            -- Try pattern-based lookup for similar programs
            similarResults <- findSimilarPrograms program cache
            case similarResults of
                [] -> do
                    let newStats = incrementMisses (statistics cache)
                    return (Nothing, cache { statistics = newStats })
                (similarEntry:_) -> do
                    -- Update usage statistics for similarity hit
                    now <- getCurrentTime
                    let updatedEntry = similarEntry { entryLastUsed = now, entryUseCount = entryUseCount similarEntry + 1 }
                        updatedEntries = Map.insert (show (entryProgram updatedEntry)) updatedEntry (cacheEntries cache)
                        -- Estimate time saved (assuming ~0.1ms average execution time)
                        timeSavedMs = 0.1
                        newStats = incrementHits $ incrementSimilarityHits $ incrementExecutionsSaved $ 
                                  addTimeSaved timeSavedMs (statistics cache)
                        -- Create a simple ProgramResult from cached data
                        programResult = ProgramResult
                            { resultOutput = entryOutputLength updatedEntry
                            , resultSteps = 0
                            , resultTermination = Halt
                            , resultProgram = entryProgram updatedEntry
                            , resultTrace = ExecutionTrace [] 0 (ExecutionState 0 0 0 0 0 Nothing)
                            , resultTimestamp = entryLastUsed updatedEntry
                            }
                    return (Just programResult, cache { cacheEntries = updatedEntries, statistics = newStats })
        Just entry -> do
            -- Direct cache hit - create ProgramResult from cached data
            now <- getCurrentTime
            let updatedEntry = entry { entryLastUsed = now, entryUseCount = entryUseCount entry + 1 }
                updatedEntries = Map.insert programKey updatedEntry (cacheEntries cache)
                -- Estimate time saved for exact match
                timeSavedMs = 0.1
                newStats = incrementHits $ incrementExecutionsSaved $ addTimeSaved timeSavedMs (statistics cache)
                -- Create a simple ProgramResult from cached data
                programResult = ProgramResult
                    { resultOutput = entryOutputLength entry
                    , resultSteps = 0  -- We don't store steps in simplified cache
                    , resultTermination = Halt  -- Assume successful termination if cached
                    , resultProgram = entryProgram entry
                    , resultTrace = ExecutionTrace [] 0 (ExecutionState 0 0 0 0 0 Nothing)  -- No trace data in simplified cache
                    , resultTimestamp = entryLastUsed entry
                    }
            return (Just programResult, cache { cacheEntries = updatedEntries, statistics = newStats })

-- | Add a program with pattern analysis to the cache
addPatternAnalysis :: [Byte] -> ProgramResult -> AdvancedPatternCache -> IO AdvancedPatternCache
addPatternAnalysis program result cache@AdvancedPatternCache{..} = do
    now <- getCurrentTime
    let programKey = show program
        entry = PatternEntry
            { entryProgram = program
            , entryOutputLength = resultOutput result
            , entryCreatedAt = now
            , entryLastUsed = now
            , entryUseCount = 1
            }
        
        -- Update main cache
        newEntries = Map.insert programKey entry cacheEntries
        
        -- Update statistics (this represents a program that was executed)
        newStats = incrementPatterns $ incrementTotalExecutions statistics
    
    return cache 
        { cacheEntries = newEntries
        , statistics = newStats
        }

-- | Find programs with similar patterns (simplified version)
findSimilarPrograms :: [Byte] -> AdvancedPatternCache -> IO [PatternEntry]
findSimilarPrograms program cache = do
    -- Simple similarity matching based on program length
    let allEntries = Map.elems (cacheEntries cache)
        similarEntries = filter (isSimilarProgram program) allEntries
    return $ take 5 similarEntries
  where
    isSimilarProgram :: [Byte] -> PatternEntry -> Bool
    isSimilarProgram prog entry = 
        -- Strict similarity: programs must be identical for now
        -- TODO: Implement proper pattern-based similarity later
        prog == entryProgram entry


-- | Get cache statistics
getCacheStatistics :: AdvancedPatternCache -> CacheStatistics
getCacheStatistics = statistics

-- | Save advanced cache to file
saveAdvancedCache :: String -> AdvancedPatternCache -> IO ()
saveAdvancedCache filepath cache = do
    result <- tryIOError $ encodeFile filepath cache
    case result of
        Left err -> putStrLn $ "Warning: Could not save cache to " ++ filepath ++ ": " ++ show err
        Right _ -> return ()  -- Success - no output needed for quiet operation

-- | Load advanced cache from file
loadAdvancedCache :: String -> IO AdvancedPatternCache
loadAdvancedCache filepath = do
    exists <- doesFileExist filepath
    if exists
        then do
            result <- tryIOError $ eitherDecodeFileStrict filepath
            case result of
                Left ioErr -> do
                    putStrLn $ "Warning: Could not read cache file " ++ filepath ++ ": " ++ show ioErr
                    createAdvancedCache
                Right (Left parseErr) -> do
                    putStrLn $ "Warning: Could not parse cache file " ++ filepath ++ ": " ++ parseErr
                    createAdvancedCache
                Right (Right cache) -> return cache
        else createAdvancedCache

-- Helper functions (from PatternCache)
incrementHits :: CacheStatistics -> CacheStatistics
incrementHits stats = stats { cacheHits = cacheHits stats + 1 }

incrementMisses :: CacheStatistics -> CacheStatistics
incrementMisses stats = stats { cacheMisses = cacheMisses stats + 1 }

incrementPatterns :: CacheStatistics -> CacheStatistics
incrementPatterns stats = stats { totalPatterns = totalPatterns stats + 1 }