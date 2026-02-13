{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Vector-based wildcard pattern cache implementation
-- Direct pattern storage with linear scan lookup, optimized for cache-friendly memory layout
module WildcardCache.Vector
    ( VectorPatternCache
    , createVectorCache
    , emptyVectorCache
    ) where

import WildcardCache.Types
import WildcardPattern 
    ( OptimizedProgram
    , matchesPattern
    , wildcardPatternBitmask
    )
import TrackedProcessor (Byte)
import qualified Data.Vector as Vector
import qualified Data.Vector as BVector
import qualified Data.List
import Data.Time (UTCTime)
import qualified Control.Exception
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import Data.Bits (popCount)
import Data.Word (Word16)


-- | Vector-based pattern cache: stores patterns in contiguous vector
-- Uses simplified storage without bitmap tuple to avoid forward declarations
data VectorPatternCache = VectorPatternCache
    { cachedPrograms :: Vector.Vector OptimizedProgram              -- All cached programs
    , patternCount :: Int                                            -- Number of cached patterns
    , cacheStats :: CacheStats                                       -- Performance statistics
    , config :: CacheConfig                                          -- Configuration
    , lastModified :: Maybe UTCTime                                  -- Last modification time
    } deriving (Show)


-- | Create empty vector cache with configuration
emptyVectorCache :: CacheConfig -> VectorPatternCache
emptyVectorCache cfg = VectorPatternCache
    { cachedPrograms = Vector.empty
    , patternCount = 0
    , cacheStats = CacheStats 0 0 0 0 0.0 0
    , config = cfg
    , lastModified = Nothing
    }


-- | Create vector cache with default configuration
createVectorCache :: CacheConfig -> IO VectorPatternCache
createVectorCache cfg = return (emptyVectorCache cfg)


-- | Estimate memory usage of cache in bytes
estimateMemoryUsage :: Vector.Vector OptimizedProgram -> Int
estimateMemoryUsage vec =
    let numPatterns = Vector.length vec
        bytesPerProgram = 240     -- Rough estimate: 16 Word16s (32 bytes) + metadata
    in numPatterns * bytesPerProgram


-- | Calculate pattern specificity (number of constrained positions)
-- Higher specificity = more Required positions, fewer Wildcards
-- BitmapPattern is BVector.Vector Word16 (16 elements)
calculateSpecificity :: BVector.Vector Word16 -> Int
calculateSpecificity bitmask =
    let countSpecific :: Word16 -> Int
        countSpecific mask = if popCount mask == 1 then 1 else 0  -- Single bit = Required
    in BVector.sum (BVector.map countSpecific bitmask)


-- | Sort patterns by specificity (most specific first)
-- More specific patterns are more likely to match, so check them first
-- Uses simple list sort for now (can optimize with vector-algorithms later)
sortPatternsBySpecificity :: Vector.Vector OptimizedProgram -> Vector.Vector OptimizedProgram
sortPatternsBySpecificity vec =
    let compareBySpecificity prog1 prog2 =
            let spec1 = calculateSpecificity (wildcardPatternBitmask prog1)
                spec2 = calculateSpecificity (wildcardPatternBitmask prog2)
            in compare spec2 spec1  -- Descending order (most specific first)
        sorted = Data.List.sortBy compareBySpecificity (Vector.toList vec)
    in Vector.fromList sorted


-- | Linear scan lookup (for small caches or fallback)
linearScanLookup :: [Byte] -> Vector.Vector OptimizedProgram -> Maybe OptimizedProgram
linearScanLookup program patterns =
    Vector.find (matchesPattern program) patterns


-- | Binary search-assisted lookup (for large caches)
-- Uses specificity to narrow down the search range, then linear scan
binarySearchLookup :: [Byte] -> Vector.Vector OptimizedProgram -> Maybe OptimizedProgram
binarySearchLookup program patterns =
    -- For now, just use linear scan - true binary search optimization can be added later
    -- when we have more sophisticated range detection
    linearScanLookup program patterns


instance WildcardPatternCache VectorPatternCache where
    -- | Lookup with adaptive strategy: linear for small caches, binary search for large
    lookupPattern program cache =
        let patterns = cachedPrograms cache
            patternCnt = Vector.length patterns
        in if patternCnt < 1000
            then linearScanLookup program patterns
            else binarySearchLookup program patterns

    -- | Insert new pattern (sort only when approaching binary search threshold)
    insertPattern optProg cache = 
        let newCount = patternCount cache + 1
            newVector = Vector.snoc (cachedPrograms cache) optProg
            
            -- Only sort when we reach 1000 patterns (binary search threshold)
            -- This defers sorting until it's actually needed
            needsSort = newCount == 1000
            sortedVector = if needsSort
                          then sortPatternsBySpecificity newVector
                          else newVector
            
            -- Update statistics
            newStats = (cacheStats cache) 
                { totalPatterns = newCount
                , memoryUsage = estimateMemoryUsage sortedVector
                }
        in cache 
            { cachedPrograms = sortedVector
            , patternCount = newCount
            , cacheStats = newStats
            }

    -- | Create an empty cache
    emptyCache = emptyVectorCache (CacheConfig Nothing False Nothing)

    -- | Get cache statistics for monitoring
    getCacheStats = cacheStats


instance PersistentCache VectorPatternCache where
    -- | Save entire cache to file as JSON array
    saveCache filePath cache = do
        (do
            writeFile filePath (show $ Aeson.toJSON cache)
            return $ Right ()) `Control.Exception.catch` 
            (\e -> return $ Left $ SaveError $ show (e :: Control.Exception.SomeException))
    
    -- | Load cache from file (sorts patterns on load)
    loadCache filePath = do
        (do
            jsonString <- readFile filePath
            case Aeson.decode $ read jsonString of
                Just (cache :: VectorPatternCache) -> do
                    -- Sort patterns by specificity after loading
                    let sortedPrograms = sortPatternsBySpecificity (cachedPrograms cache)
                        sortedCache = cache { cachedPrograms = sortedPrograms }
                    return $ Right sortedCache
                Nothing -> return $ Left $ LoadError "Failed to parse JSON") `Control.Exception.catch`
            (\e -> return $ Left $ LoadError $ show (e :: Control.Exception.SomeException))
    
    -- | Incrementally update persistent storage
    appendToCache filePath optProg cache = do
        let updatedCache = insertPattern optProg cache
        saveResult <- saveCache filePath updatedCache
        case saveResult of
            Left err -> return $ Left err
            Right _ -> return $ Right updatedCache


-- JSON serialization instances for persistence
instance ToJSON VectorPatternCache where
    toJSON cache = Aeson.object
        [ Key.fromString "cachedPrograms" .= Vector.toList (cachedPrograms cache)
        , Key.fromString "patternCount" .= patternCount cache
        , Key.fromString "cacheStats" .= cacheStats cache
        , Key.fromString "config" .= config cache
        ]

instance FromJSON VectorPatternCache where
    parseJSON = Aeson.withObject "VectorPatternCache" $ \o -> VectorPatternCache
        <$> (Vector.fromList <$> o .: Key.fromString "cachedPrograms")
        <*> o .: Key.fromString "patternCount"
        <*> o .: Key.fromString "cacheStats"
        <*> o .: Key.fromString "config"
        <*> pure Nothing  -- lastModified not serialized
