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
    )
import qualified Data.Vector as Vector
import Data.Time (UTCTime)
import qualified Control.Exception
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key


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


instance WildcardPatternCache VectorPatternCache where
    -- | Linear scan lookup through pattern vector
    -- Matches raw program against each cached pattern using bitmap matching
    lookupPattern program cache = 
        Vector.find (matchesPattern program) (cachedPrograms cache)

    -- | Insert new pattern, maintaining vector
    insertPattern optProg cache = 
        let newVector = Vector.snoc (cachedPrograms cache) optProg
            
            -- Update statistics
            newStats = (cacheStats cache) 
                { totalPatterns = patternCount cache + 1
                , memoryUsage = estimateMemoryUsage newVector
                }
        in cache 
            { cachedPrograms = newVector
            , patternCount = patternCount cache + 1
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
    
    -- | Load cache from file
    loadCache filePath = do
        (do
            jsonString <- readFile filePath
            case Aeson.decode $ read jsonString of
                Just (cache :: VectorPatternCache) -> return $ Right cache
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
