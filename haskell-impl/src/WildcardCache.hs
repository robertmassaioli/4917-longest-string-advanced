{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RankNTypes #-}

-- | Standard interface and common types for wildcard pattern caching
module WildcardCache
    ( -- * Core Interface
      WildcardPatternCache(..)
    , PersistentCache(..)
    , CacheStats(..)
    , CacheConfig(..)
    , SaveError(..)
    , LoadError(..)
    
    -- * Implementation Selection
    , CacheImplementation(..)
    , SomeCacheImpl(..)
    , lookupInCache
    , insertIntoCache
    , extractCacheStats
    
    -- * Search Integration
    , SearchResults(..)
    , optimizedSearch
    ) where

import WildcardPattern (OptimizedProgram)
import TrackedProcessor (Byte)

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

-- | Cache implementation selection
data CacheImplementation 
    = VectorScanCache
    | TrieCache  
    | PositionIndexCache
    | BitMatrixCache
    | DFACache
    | SignatureHashCache  -- Available but not recommended
    deriving (Show, Eq, Enum, Bounded)

-- | Existential wrapper for different cache implementations
data SomeCacheImpl = forall cache. (WildcardPatternCache cache, PersistentCache cache) => 
    SomeCache cache


-- | Unified interface operations
lookupInCache :: [Byte] -> SomeCacheImpl -> Maybe OptimizedProgram
lookupInCache program (SomeCache cache) = lookupPattern program cache

insertIntoCache :: OptimizedProgram -> SomeCacheImpl -> SomeCacheImpl  
insertIntoCache optProg (SomeCache cache) = SomeCache (insertPattern optProg cache)

-- | Extract cache statistics from existential wrapper
extractCacheStats :: SomeCacheImpl -> CacheStats
extractCacheStats (SomeCache cache) = getCacheStats cache

-- | Search results with performance metrics
data SearchResults = SearchResults
    { bestPrograms :: [(Int, [Byte], Int)]  -- (length, program, output)
    , cachePerformance :: CacheStats        -- Cache performance metrics
    } deriving (Show)

-- | Main search function that works with any cache implementation
-- Note: This is a placeholder - actual implementation would be provided by specific commands
optimizedSearch :: CacheImplementation -> CacheConfig -> Int -> IO SearchResults
optimizedSearch cacheImpl _config maxLength = do
    -- Placeholder implementation
    putStrLn $ "Running optimized search with " ++ show cacheImpl ++ " up to length " ++ show maxLength
    return $ SearchResults [] (CacheStats 0 0 0 0 0.0 0)