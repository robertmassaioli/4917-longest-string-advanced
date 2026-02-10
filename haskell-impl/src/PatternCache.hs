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
    ) where

import ExecutionTracing (ProgramResult(..), TerminationType(Halt, Timeout, InfiniteLoop, Error))
import Processor (Byte)
import Data.Time (UTCTime, getCurrentTime)
import Data.Aeson
import Data.Aeson.Types (parseMaybe)
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
    } deriving (Show, Eq, Generic)

instance NFData CacheStatistics where
    rnf (CacheStatistics tp ch cm lu) = 
        rnf tp `seq` rnf ch `seq` rnf cm `seq` rnf lu

instance ToJSON CacheStatistics where
    toJSON (CacheStatistics tp ch cm lu) = object
        [ "total_patterns" .= tp
        , "cache_hits" .= ch  
        , "cache_misses" .= cm
        , "last_updated" .= lu
        ]

instance FromJSON CacheStatistics where
    parseJSON = withObject "CacheStatistics" $ \o -> CacheStatistics
        <$> o .: "total_patterns"
        <*> o .: "cache_hits"
        <*> o .: "cache_misses"
        <*> o .: "last_updated"

-- | Simplified pattern result for caching
data PatternResult = PatternResult
    { patternOutput :: String
    , patternSteps :: Int
    , patternTermination :: TerminationType
    , patternConfidence :: Double
    } deriving (Show, Eq, Ord, Generic)

instance NFData PatternResult where
    rnf (PatternResult out steps term conf) = 
        rnf out `seq` rnf steps `seq` rnf term `seq` rnf conf

instance ToJSON TerminationType where
    toJSON Halt = "halt"
    toJSON Timeout = "timeout"  
    toJSON InfiniteLoop = "loop"
    toJSON ExecutionTracing.Error = "error"

instance FromJSON TerminationType where
    parseJSON = withText "TerminationType" $ \case
        "halt" -> pure Halt
        "timeout" -> pure Timeout
        "loop" -> pure InfiniteLoop
        "error" -> pure ExecutionTracing.Error
        _ -> fail "Unknown termination type"

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
        , cacheStatistics = CacheStatistics 0 0 0 now
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