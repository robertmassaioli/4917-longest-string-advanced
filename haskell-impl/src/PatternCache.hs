{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module PatternCache
    ( ProgramCache(..)
    , CacheStatistics(..)
    , PatternEntry(..)
    , PatternResult(..)
    , loadCache
    , saveCache
    , emptyCache
    , lookupPattern
    , addPatternEntry
    , updateStatistics
    , incrementExecutionsSaved
    , incrementWildcardHits
    , incrementSimilarityHits
    , incrementTotalExecutions
    , addTimeSaved
    ) where

import ExecutionTracing (ProgramResult(..), TerminationType(..))
import Processor (Byte)
import Data.Time (UTCTime, getCurrentTime)
import Data.Aeson
import GHC.Generics (Generic)
import Control.DeepSeq (NFData, rnf)
import qualified Data.Map as Map
import Data.Map (Map)
import System.IO.Error (catchIOError)

-- | Cache statistics for monitoring performance
data CacheStatistics = CacheStatistics
    { totalPatterns :: Int
    , cacheHits :: Int
    , cacheMisses :: Int
    , lastUpdated :: UTCTime
    , executionsSaved :: Int        -- Programs that didn't need execution due to cache
    , wildcardHits :: Int          -- Cache hits via wildcard pattern matching
    , similarityHits :: Int        -- Cache hits via structural similarity  
    , totalExecutions :: Int       -- Total programs actually executed (not cached)
    , estimatedTimeSavedMs :: Double -- Estimated milliseconds saved by caching
    } deriving (Show, Eq, Generic)

instance NFData CacheStatistics where
    rnf (CacheStatistics tp ch cm lu es wh sh te ts) = 
        rnf tp `seq` rnf ch `seq` rnf cm `seq` rnf lu `seq` 
        rnf es `seq` rnf wh `seq` rnf sh `seq` rnf te `seq` rnf ts

instance ToJSON CacheStatistics where
    toJSON (CacheStatistics tp ch cm lu es wh sh te ts) = object
        [ "total_patterns" .= tp
        , "cache_hits" .= ch  
        , "cache_misses" .= cm
        , "last_updated" .= lu
        , "executions_saved" .= es
        , "wildcard_hits" .= wh
        , "similarity_hits" .= sh
        , "total_executions" .= te
        , "estimated_time_saved_ms" .= ts
        ]

instance FromJSON CacheStatistics where
    parseJSON = withObject "CacheStatistics" $ \o -> CacheStatistics
        <$> o .: "total_patterns"
        <*> o .: "cache_hits"
        <*> o .: "cache_misses"
        <*> o .: "last_updated"
        <*> o .:? "executions_saved" .!= 0
        <*> o .:? "wildcard_hits" .!= 0
        <*> o .:? "similarity_hits" .!= 0
        <*> o .:? "total_executions" .!= 0
        <*> o .:? "estimated_time_saved_ms" .!= 0.0

-- | Simplified pattern result for caching
data PatternResult = PatternResult
    { patternOutput :: Int
    , patternSteps :: Int
    , patternTermination :: TerminationType
    , patternConfidence :: Double
    } deriving (Show, Eq, Ord, Generic)

instance NFData PatternResult where
    rnf (PatternResult out steps term conf) = 
        rnf out `seq` rnf steps `seq` rnf term `seq` rnf conf


instance ToJSON PatternResult where
    toJSON (PatternResult out steps term conf) = object
        [ "output" .= out
        , "steps" .= steps
        , "termination" .= term
        , "confidence" .= conf
        ]

instance FromJSON PatternResult where
    parseJSON = withObject "PatternResult" $ \o -> PatternResult
        <$> o .: "output"
        <*> o .: "steps" 
        <*> o .: "termination"
        <*> o .: "confidence"

-- | Cache entry for a specific pattern
data PatternEntry = PatternEntry
    { entryPattern :: [Byte]
    , entryResult :: PatternResult
    , entryMatchCount :: Int
    , entryCreated :: UTCTime
    , entryLastUsed :: UTCTime
    } deriving (Show, Eq, Generic)

instance NFData PatternEntry where
    rnf (PatternEntry pat res mc created used) = 
        rnf pat `seq` rnf res `seq` rnf mc `seq` rnf created `seq` rnf used

instance ToJSON PatternEntry where
    toJSON (PatternEntry pat res mc created used) = object
        [ "pattern" .= pat
        , "result" .= res
        , "match_count" .= mc
        , "created" .= created
        , "last_used" .= used
        ]

instance FromJSON PatternEntry where
    parseJSON = withObject "PatternEntry" $ \o -> PatternEntry
        <$> o .: "pattern"
        <*> o .: "result"
        <*> o .: "match_count"
        <*> o .: "created"
        <*> o .: "last_used"

-- | Main cache structure
data ProgramCache = ProgramCache
    { cacheFilePath :: FilePath
    , cachePatterns :: Map String PatternEntry  -- Key: program pattern as string
    , cacheStatistics :: CacheStatistics
    , cacheVersion :: String
    } deriving (Show, Eq, Generic)

instance NFData ProgramCache where
    rnf (ProgramCache path patterns stats version) = 
        rnf path `seq` rnf patterns `seq` rnf stats `seq` rnf version

instance ToJSON ProgramCache where
    toJSON (ProgramCache _ patterns stats version) = object
        [ "cache_version" .= version
        , "statistics" .= stats
        , "patterns" .= Map.toList patterns  -- Convert Map to list for JSON
        ]

instance FromJSON ProgramCache where
    parseJSON = withObject "ProgramCache" $ \o -> do
        version <- o .: "cache_version"
        stats <- o .: "statistics"
        patternsList <- o .: "patterns"
        let patterns = Map.fromList patternsList
        pure $ ProgramCache "" patterns stats version

-- | Create empty cache
emptyCache :: FilePath -> IO ProgramCache
emptyCache filepath = do
    now <- getCurrentTime
    return ProgramCache
        { cacheFilePath = filepath
        , cachePatterns = Map.empty
        , cacheStatistics = CacheStatistics 0 0 0 now 0 0 0 0 0.0
        , cacheVersion = "1.0"
        }

-- | Load cache from file, create empty if file doesn't exist
loadCache :: FilePath -> IO ProgramCache
loadCache filepath = do
    result <- catchIOError (eitherDecodeFileStrict filepath) handleError
    case result of
        Left err -> do
            putStrLn $ "Cache load failed: " ++ err ++ ". Creating new cache."
            emptyCache filepath
        Right cache -> return cache { cacheFilePath = filepath }
  where
    handleError _ = return (Left "File not found")

-- | Save cache to file
saveCache :: ProgramCache -> IO ()
saveCache cache = do
    now <- getCurrentTime
    let updatedStats = (cacheStatistics cache) { lastUpdated = now }
        updatedCache = cache { cacheStatistics = updatedStats }
    encodeFile (cacheFilePath cache) updatedCache

-- | Look up a program pattern in the cache
lookupPattern :: [Byte] -> ProgramCache -> IO (Maybe PatternResult, ProgramCache)
lookupPattern program cache = do
    now <- getCurrentTime
    let patternKey = show program
    case Map.lookup patternKey (cachePatterns cache) of
        Nothing -> do
            let newStats = incrementMisses (cacheStatistics cache)
            return (Nothing, cache { cacheStatistics = newStats })
        Just entry -> do
            let updatedEntry = entry { entryLastUsed = now, entryMatchCount = entryMatchCount entry + 1 }
                updatedPatterns = Map.insert patternKey updatedEntry (cachePatterns cache)
                newStats = incrementHits (cacheStatistics cache)
                updatedCache = cache { cachePatterns = updatedPatterns, cacheStatistics = newStats }
            return (Just (entryResult entry), updatedCache)

-- | Add a new pattern entry to the cache
addPatternEntry :: [Byte] -> ProgramResult -> ProgramCache -> IO ProgramCache
addPatternEntry program result cache = do
    now <- getCurrentTime
    let patternKey = show program
        patternResult = PatternResult
            { patternOutput = resultOutput result
            , patternSteps = resultSteps result
            , patternTermination = resultTermination result
            , patternConfidence = 1.0  -- Initial confidence
            }
        entry = PatternEntry
            { entryPattern = program
            , entryResult = patternResult
            , entryMatchCount = 1
            , entryCreated = now
            , entryLastUsed = now
            }
        updatedPatterns = Map.insert patternKey entry (cachePatterns cache)
        newStats = incrementPatterns (cacheStatistics cache)
    return cache { cachePatterns = updatedPatterns, cacheStatistics = newStats }

-- | Update cache statistics
updateStatistics :: ProgramCache -> IO ProgramCache
updateStatistics cache = do
    now <- getCurrentTime
    let newStats = (cacheStatistics cache) { lastUpdated = now }
    return cache { cacheStatistics = newStats }

-- Helper functions for statistics
incrementHits :: CacheStatistics -> CacheStatistics
incrementHits stats = stats { cacheHits = cacheHits stats + 1 }

incrementMisses :: CacheStatistics -> CacheStatistics
incrementMisses stats = stats { cacheMisses = cacheMisses stats + 1 }

incrementPatterns :: CacheStatistics -> CacheStatistics
incrementPatterns stats = stats { totalPatterns = totalPatterns stats + 1 }

-- New helper functions for execution tracking
incrementExecutionsSaved :: CacheStatistics -> CacheStatistics
incrementExecutionsSaved stats = stats { executionsSaved = executionsSaved stats + 1 }

incrementWildcardHits :: CacheStatistics -> CacheStatistics
incrementWildcardHits stats = stats { wildcardHits = wildcardHits stats + 1 }

incrementSimilarityHits :: CacheStatistics -> CacheStatistics
incrementSimilarityHits stats = stats { similarityHits = similarityHits stats + 1 }

incrementTotalExecutions :: CacheStatistics -> CacheStatistics
incrementTotalExecutions stats = stats { totalExecutions = totalExecutions stats + 1 }

addTimeSaved :: Double -> CacheStatistics -> CacheStatistics
addTimeSaved timeMs stats = stats { estimatedTimeSavedMs = estimatedTimeSavedMs stats + timeMs }