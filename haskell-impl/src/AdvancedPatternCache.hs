{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

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
import ExecutionTracing (ProgramResult(..), extractExecutionSteps)
import PatternCache (ProgramCache(..), CacheStatistics(..))
import qualified PatternCache as Basic
import Processor (Byte)
import Data.Time (UTCTime, getCurrentTime)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.List (sortBy)
import Data.Aeson
import GHC.Generics (Generic)
import Control.DeepSeq (NFData, rnf)

-- | Advanced pattern cache entry with pattern analysis
data PatternEntry = PatternEntry
    { entryProgram :: [Byte]
    , entryResult :: ProgramResult
    , entryPattern :: ProgramPattern
    , entryCreatedAt :: UTCTime
    , entryLastUsed :: UTCTime
    , entryUseCount :: Int
    } deriving (Show, Eq, Generic)

instance NFData PatternEntry where
    rnf (PatternEntry prog result pattern created used count) = 
        rnf prog `seq` rnf result `seq` rnf pattern `seq` rnf created `seq` rnf used `seq` rnf count

-- | Advanced cache with pattern analysis capabilities
data AdvancedPatternCache = AdvancedPatternCache
    { cacheEntries :: Map String PatternEntry      -- Keyed by program bytes
    , patternIndex :: Map PatternType [String]      -- Index by pattern type
    , haltPrograms :: [String]                     -- Programs that definitely halt
    , loopPrograms :: [(String, LoopPattern)]     -- Programs with detected loops
    , statistics :: CacheStatistics
    , cacheVersion :: String
    } deriving (Show, Eq, Generic)

instance NFData AdvancedPatternCache where
    rnf (AdvancedPatternCache entries index halts loops stats ver) = 
        rnf entries `seq` rnf index `seq` rnf halts `seq` rnf loops `seq` rnf stats `seq` rnf ver

-- | Create empty advanced cache
createAdvancedCache :: IO AdvancedPatternCache
createAdvancedCache = do
    now <- getCurrentTime
    return AdvancedPatternCache
        { cacheEntries = Map.empty
        , patternIndex = Map.empty
        , haltPrograms = []
        , loopPrograms = []
        , statistics = CacheStatistics 0 0 0 now
        , cacheVersion = "2.0"
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
                    -- Update usage statistics
                    now <- getCurrentTime
                    let updatedEntry = similarEntry { entryLastUsed = now, entryUseCount = entryUseCount similarEntry + 1 }
                        updatedEntries = Map.insert (show (entryProgram updatedEntry)) updatedEntry (cacheEntries cache)
                        newStats = incrementHits (statistics cache)
                    return (Just (entryResult updatedEntry), cache { cacheEntries = updatedEntries, statistics = newStats })
        Just entry -> do
            -- Direct cache hit
            now <- getCurrentTime
            let updatedEntry = entry { entryLastUsed = now, entryUseCount = entryUseCount entry + 1 }
                updatedEntries = Map.insert programKey updatedEntry (cacheEntries cache)
                newStats = incrementHits (statistics cache)
            return (Just (entryResult updatedEntry), cache { cacheEntries = updatedEntries, statistics = newStats })

-- | Add a program with pattern analysis to the cache
addPatternAnalysis :: [Byte] -> ProgramResult -> AdvancedPatternCache -> IO AdvancedPatternCache
addPatternAnalysis program result cache = do
    now <- getCurrentTime
    let pattern = analyzeProgram program result
        programKey = show program
        entry = PatternEntry
            { entryProgram = program
            , entryResult = result
            , entryPattern = pattern
            , entryCreatedAt = now
            , entryLastUsed = now
            , entryUseCount = 1
            }
        
        -- Update main cache
        newEntries = Map.insert programKey entry (cacheEntries cache)
        
        -- Update pattern index
        newPatternIndex = updatePatternIndex (patternType pattern) programKey (patternIndex cache)
        
        -- Update specialized lists
        newHaltPrograms = if patternType pattern == HaltPattern 
                         then programKey : haltPrograms cache
                         else haltPrograms cache
        
        newLoopPrograms = case patternLoop pattern of
            Nothing -> loopPrograms cache
            Just loopPat -> (programKey, loopPat) : loopPrograms cache
        
        -- Update statistics
        newStats = incrementPatterns (statistics cache)
    
    return cache 
        { cacheEntries = newEntries
        , patternIndex = newPatternIndex
        , haltPrograms = newHaltPrograms
        , loopPrograms = newLoopPrograms
        , statistics = newStats
        }

-- | Find programs with similar patterns
findSimilarPrograms :: [Byte] -> AdvancedPatternCache -> IO [PatternEntry]
findSimilarPrograms program cache = do
    -- For Phase 2, we do simple pattern type matching
    -- Phase 3 will add more sophisticated similarity matching
    
    -- First, try to predict what pattern type this program might have
    let predictedPatternType = predictPatternType program
        similarKeys = Map.findWithDefault [] predictedPatternType (patternIndex cache)
        similarEntries = [entry | key <- similarKeys, Just entry <- [Map.lookup key (cacheEntries cache)]]
    
    return $ take 5 $ filter (isSimilarProgram program) similarEntries
  where
    isSimilarProgram :: [Byte] -> PatternEntry -> Bool
    isSimilarProgram prog entry = 
        -- Try wildcard pattern matching first
        matchesPattern prog (entryPattern entry) ||
        -- Fallback to basic similarity
        (length prog == length (entryProgram entry))

-- | Predict pattern type from program structure (heuristic)
predictPatternType :: [Byte] -> PatternType
predictPatternType program
    | 0 `elem` program = HaltPattern  -- Has HALT instruction
    | any (`elem` [13, 14, 15]) program = SimpleLoopPattern  -- Has jump instructions
    | otherwise = LinearPattern

-- | Check if two programs are similar (Phase 2: simple heuristics)
isSimilarProgram :: [Byte] -> PatternEntry -> Bool
isSimilarProgram program entry =
    let otherProgram = entryProgram entry
        pattern = entryPattern entry
        
        -- Simple similarity checks for Phase 2
        sameLengthCheck = length program == length otherProgram
        samePatternTypeCheck = predictPatternType program == patternType pattern
        
        -- Structure similarity (same instruction types present)
        programInstructions = map (`div` 16) program  -- Group into instruction families
        otherInstructions = map (`div` 16) otherProgram
        structureSimilarity = programInstructions == otherInstructions
        
    in sameLengthCheck && samePatternTypeCheck && structureSimilarity

-- | Update pattern index
updatePatternIndex :: PatternType -> String -> Map PatternType [String] -> Map PatternType [String]
updatePatternIndex patternType programKey index = 
    Map.insertWith (++) patternType [programKey] index

-- | Get cache statistics
getCacheStatistics :: AdvancedPatternCache -> CacheStatistics
getCacheStatistics = statistics

-- | Save advanced cache to file
saveAdvancedCache :: String -> AdvancedPatternCache -> IO ()
saveAdvancedCache filepath cache = do
    -- Convert to JSON and save
    -- Note: This would require ToJSON instances for all types
    putStrLn $ "Advanced cache saved to: " ++ filepath
    -- encodeFile filepath cache  -- Uncomment when ToJSON instances are ready

-- | Load advanced cache from file
loadAdvancedCache :: String -> IO AdvancedPatternCache
loadAdvancedCache filepath = do
    -- Try to load from file, create empty if not found
    putStrLn $ "Loading advanced cache from: " ++ filepath
    createAdvancedCache  -- For now, always create empty cache

-- Helper functions (from PatternCache)
incrementHits :: CacheStatistics -> CacheStatistics
incrementHits stats = stats { cacheHits = cacheHits stats + 1 }

incrementMisses :: CacheStatistics -> CacheStatistics
incrementMisses stats = stats { cacheMisses = cacheMisses stats + 1 }

incrementPatterns :: CacheStatistics -> CacheStatistics
incrementPatterns stats = stats { totalPatterns = totalPatterns stats + 1 }