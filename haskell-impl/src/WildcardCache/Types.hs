-- | Shared types for all wildcard cache implementations
module WildcardCache.Types
    ( CacheStats(..)
    , CacheConfig(..)
    , SaveError(..)
    , LoadError(..)
    , WildcardPatternCache(..)
    , PersistentCache(..)
    ) where

import WildcardPattern (OptimizedProgram)
import TrackedProcessor (Byte)
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key

-- | Cache performance and usage statistics
data CacheStats = CacheStats
    { totalPatterns :: Int          -- Number of cached patterns
    , totalLookups :: Int           -- Number of lookup attempts
    , cacheHits :: Int              -- Successful pattern matches
    , cacheMisses :: Int            -- Programs that needed execution
    , avgLookupTime :: Double       -- Average lookup time in microseconds
    , memoryUsage :: Int            -- Approximate memory usage in bytes
    } deriving (Show, Eq)

-- | Cache configuration for different implementations
data CacheConfig = CacheConfig
    { maxPatterns :: Maybe Int      -- Maximum patterns to cache (Nothing = unlimited)
    , enableStats :: Bool           -- Whether to track performance statistics
    , persistenceFile :: Maybe FilePath  -- Optional file for persistence
    } deriving (Show, Eq)

-- | Standardized error types
data SaveError = SaveError String deriving (Show, Eq)
data LoadError = LoadError String deriving (Show, Eq)

-- | Generic pattern cache interface that all implementations must support
class WildcardPatternCache cache where
    -- | Check if a raw program matches any cached wildcard pattern (NO EXECUTION!)
    lookupPattern :: [Byte] -> cache -> Maybe OptimizedProgram
    
    -- | Insert a new OptimizedProgram into the cache
    insertPattern :: OptimizedProgram -> cache -> cache
    
    -- | Create an empty cache
    emptyCache :: cache
    
    -- | Get cache statistics for monitoring
    getCacheStats :: cache -> CacheStats

-- | Standardized persistence operations
class (WildcardPatternCache cache) => PersistentCache cache where
    -- | Save cache to filesystem
    saveCache :: FilePath -> cache -> IO (Either SaveError ())
    
    -- | Load cache from filesystem  
    loadCache :: FilePath -> IO (Either LoadError cache)
    
    -- | Incrementally update persistent storage (for append-friendly implementations)
    appendToCache :: FilePath -> OptimizedProgram -> cache -> IO (Either SaveError cache)

-- JSON serialization instances
instance ToJSON CacheStats where
    toJSON stats = Aeson.object
        [ Key.fromString "totalPatterns" .= totalPatterns stats
        , Key.fromString "totalLookups" .= totalLookups stats  
        , Key.fromString "cacheHits" .= cacheHits stats
        , Key.fromString "cacheMisses" .= cacheMisses stats
        , Key.fromString "avgLookupTime" .= avgLookupTime stats
        , Key.fromString "memoryUsage" .= memoryUsage stats
        ]

instance FromJSON CacheStats where
    parseJSON = Aeson.withObject "CacheStats" $ \o -> CacheStats
        <$> o .: Key.fromString "totalPatterns"
        <*> o .: Key.fromString "totalLookups"
        <*> o .: Key.fromString "cacheHits"
        <*> o .: Key.fromString "cacheMisses"
        <*> o .: Key.fromString "avgLookupTime"
        <*> o .: Key.fromString "memoryUsage"

instance ToJSON CacheConfig where
    toJSON config = Aeson.object
        [ Key.fromString "maxPatterns" .= maxPatterns config
        , Key.fromString "enableStats" .= enableStats config
        , Key.fromString "persistenceFile" .= persistenceFile config
        ]

instance FromJSON CacheConfig where
    parseJSON = Aeson.withObject "CacheConfig" $ \o -> CacheConfig
        <$> o .: Key.fromString "maxPatterns"
        <*> o .: Key.fromString "enableStats"
        <*> o .: Key.fromString "persistenceFile"