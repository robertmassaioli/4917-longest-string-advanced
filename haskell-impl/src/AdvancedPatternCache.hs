{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

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
import qualified LegacyWildcardPatterns as WP
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

-- | Enhanced pattern cache entry with wildcard pattern support
data PatternEntry = PatternEntry
    { entryProgram :: [Byte]
    , entryOutputLength :: Int
    , entryCreatedAt :: UTCTime
    , entryLastUsed :: UTCTime
    , entryUseCount :: Int
    , entryPattern :: Maybe ProgramPattern  -- Analyzed pattern with wildcard
    } deriving (Show, Eq, Generic, ToJSON, FromJSON)

instance NFData PatternEntry where
    rnf (PatternEntry prog output created used count pattern) = 
        rnf prog `seq` rnf output `seq` rnf created `seq` rnf used `seq` rnf count `seq` rnf pattern

-- | Advanced cache with wildcard pattern support
data AdvancedPatternCache = AdvancedPatternCache
    { cacheEntries :: Map String PatternEntry      -- Keyed by program bytes
    , wildcardPatterns :: [ProgramPattern]         -- Reusable wildcard patterns
    , statistics :: CacheStatistics
    , cacheVersion :: String
    } deriving (Show, Eq, Generic, ToJSON, FromJSON)

instance NFData AdvancedPatternCache where
    rnf (AdvancedPatternCache entries patterns stats ver) = 
        rnf entries `seq` rnf patterns `seq` rnf stats `seq` rnf ver

-- | Create empty advanced cache
createAdvancedCache :: IO AdvancedPatternCache
createAdvancedCache = do
    now <- getCurrentTime
    return AdvancedPatternCache
        { cacheEntries = Map.empty
        , wildcardPatterns = []
        , statistics = CacheStatistics 0 0 0 now 0 0 0 0 0.0
        , cacheVersion = "4.0"  -- Increment version for new wildcard support
        }

-- | Look up a program by its pattern characteristics with wildcard matching
lookupByPattern :: [Byte] -> AdvancedPatternCache -> IO (Maybe ProgramResult, AdvancedPatternCache)
lookupByPattern program cache = do
    let programKey = show program
    case Map.lookup programKey (cacheEntries cache) of
        Nothing -> do
            -- Try wildcard pattern matching first
            wildcardMatch <- findWildcardMatch program cache
            case wildcardMatch of
                Just (matchedEntry, hitType) -> do
                    -- Wildcard hit - update statistics and return result
                    now <- getCurrentTime
                    let updatedEntry = matchedEntry { entryLastUsed = now, entryUseCount = entryUseCount matchedEntry + 1 }
                        updatedEntries = Map.insert (show (entryProgram updatedEntry)) updatedEntry (cacheEntries cache)
                        timeSavedMs = 0.15  -- Slightly more time saved due to pattern matching
                        newStats = case hitType of
                            WildcardHit -> incrementHits $ incrementWildcardHits $ incrementExecutionsSaved $ 
                                         addTimeSaved timeSavedMs (statistics cache)
                            SimilarityHit -> incrementHits $ incrementSimilarityHits $ incrementExecutionsSaved $ 
                                           addTimeSaved timeSavedMs (statistics cache)
                        programResult = ProgramResult
                            { resultOutput = entryOutputLength updatedEntry
                            , resultSteps = 0
                            , resultTermination = Halt
                            , resultProgram = program  -- Use the queried program, not the matched one
                            , resultTrace = ExecutionTrace [] 0 (ExecutionState 0 0 0 0 0 Nothing)
                            , resultTimestamp = now
                            }
                    return (Just programResult, cache { cacheEntries = updatedEntries, statistics = newStats })
                Nothing -> do
                    -- No matches found
                    let newStats = incrementMisses (statistics cache)
                    return (Nothing, cache { statistics = newStats })
        Just entry -> do
            -- Direct cache hit - create ProgramResult from cached data
            now <- getCurrentTime
            let updatedEntry = entry { entryLastUsed = now, entryUseCount = entryUseCount entry + 1 }
                updatedEntries = Map.insert programKey updatedEntry (cacheEntries cache)
                timeSavedMs = 0.1
                newStats = incrementHits $ incrementExecutionsSaved $ addTimeSaved timeSavedMs (statistics cache)
                programResult = ProgramResult
                    { resultOutput = entryOutputLength entry
                    , resultSteps = 0
                    , resultTermination = Halt
                    , resultProgram = entryProgram entry
                    , resultTrace = ExecutionTrace [] 0 (ExecutionState 0 0 0 0 0 Nothing)
                    , resultTimestamp = entryLastUsed entry
                    }
            return (Just programResult, cache { cacheEntries = updatedEntries, statistics = newStats })

-- | Add a program with pattern analysis to the cache
addPatternAnalysis :: [Byte] -> ProgramResult -> AdvancedPatternCache -> IO AdvancedPatternCache
addPatternAnalysis program result cache@AdvancedPatternCache{..} = do
    now <- getCurrentTime
    let programKey = show program
        -- Analyze the program to create a pattern
        programPattern = analyzeProgram program result
        entry = PatternEntry
            { entryProgram = program
            , entryOutputLength = resultOutput result
            , entryCreatedAt = now
            , entryLastUsed = now
            , entryUseCount = 1
            , entryPattern = Just programPattern
            }
        
        -- Update main cache
        newEntries = Map.insert programKey entry cacheEntries
        
        -- Add to wildcard patterns if it has a reusable wildcard
        newWildcardPatterns = case patternWildcard programPattern of
            Nothing -> wildcardPatterns
            Just _ -> if shouldAddToWildcardPatterns programPattern (wildcardPatterns)
                     then programPattern : take 50 wildcardPatterns  -- Limit to 50 patterns
                     else wildcardPatterns
        
        -- Update statistics (this represents a program that was executed)
        newStats = incrementPatterns $ incrementTotalExecutions statistics
    
    return cache 
        { cacheEntries = newEntries
        , wildcardPatterns = newWildcardPatterns
        , statistics = newStats
        }

-- | Types of pattern matches
data MatchType = WildcardHit | SimilarityHit deriving (Show, Eq)

-- | Find a wildcard pattern match for the given program
findWildcardMatch :: [Byte] -> AdvancedPatternCache -> IO (Maybe (PatternEntry, MatchType))
findWildcardMatch program cache = do
    -- First try wildcard patterns from the global pattern list
    let wildcardMatch = findInWildcardPatterns program (wildcardPatterns cache)
    case wildcardMatch of
        Just matchedPattern -> do
            -- Find an entry that matches this pattern for result data
            matchingEntry <- findEntryForPattern matchedPattern cache
            case matchingEntry of
                Just entry -> return $ Just (entry, WildcardHit)
                Nothing -> return Nothing
        Nothing -> do
            -- Fall back to entry-specific pattern matching
            findSimilarPrograms program cache >>= \case
                [] -> return Nothing
                (entry:_) -> return $ Just (entry, SimilarityHit)

-- | Find matching pattern in the global wildcard patterns list
findInWildcardPatterns :: [Byte] -> [ProgramPattern] -> Maybe ProgramPattern
findInWildcardPatterns program patterns = 
    case filter (matchesPattern program) patterns of
        [] -> Nothing
        (pattern:_) -> Just pattern

-- | Find a cache entry that corresponds to a pattern (for getting result data)
findEntryForPattern :: ProgramPattern -> AdvancedPatternCache -> IO (Maybe PatternEntry)
findEntryForPattern pattern cache = do
    let allEntries = Map.elems (cacheEntries cache)
        matchingEntries = filter (\entry -> 
            case entryPattern entry of
                Nothing -> False
                Just entryPat -> patternProgram entryPat == patternProgram pattern
            ) allEntries
    return $ case matchingEntries of
        [] -> Nothing
        (entry:_) -> Just entry

-- | Find programs with similar patterns (fallback method)
findSimilarPrograms :: [Byte] -> AdvancedPatternCache -> IO [PatternEntry]
findSimilarPrograms program cache = do
    let allEntries = Map.elems (cacheEntries cache)
        similarEntries = filter (isSimilarProgram program) allEntries
    return $ take 5 similarEntries
  where
    isSimilarProgram :: [Byte] -> PatternEntry -> Bool
    isSimilarProgram prog entry = 
        case entryPattern entry of
            Nothing -> prog == entryProgram entry  -- Exact match fallback
            Just pattern -> matchesPattern prog pattern  -- Pattern-based matching

-- | Determine if a new pattern should be added to the wildcard patterns list
shouldAddToWildcardPatterns :: ProgramPattern -> [ProgramPattern] -> Bool
shouldAddToWildcardPatterns newPattern existingPatterns =
    let confidence = patternConfidenceScore newPattern
        hasWildcard = case patternWildcard newPattern of
            Nothing -> False
            Just _ -> True
        isNotDuplicate = not $ any (\p -> patternProgram p == patternProgram newPattern) existingPatterns
    in hasWildcard && confidence > 0.7 && isNotDuplicate


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