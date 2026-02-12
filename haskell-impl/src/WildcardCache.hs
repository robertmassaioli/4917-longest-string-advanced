{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RankNTypes #-}

-- | Standard interface and common types for wildcard pattern caching
module WildcardCache
    ( -- * Re-export shared types and interfaces
      module WildcardCache.Types
    
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

import WildcardCache.Types
import WildcardPattern (OptimizedProgram)
import TrackedProcessor (Byte)
import qualified CacheStatsTracker as CST (CacheStatsTracker, trackCacheHit, trackCacheMiss)

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


-- | Unified interface operations with statistics tracking
lookupInCache :: [Byte] -> SomeCacheImpl -> CST.CacheStatsTracker -> IO (Maybe OptimizedProgram)
lookupInCache program (SomeCache cache) statsTracker = do
    let result = lookupPattern program cache
    case result of
        Just _ -> CST.trackCacheHit statsTracker
        Nothing -> CST.trackCacheMiss statsTracker
    return result

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