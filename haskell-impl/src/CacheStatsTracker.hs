-- | Separate statistics tracking for cache operations
-- This module provides mutable statistics tracking that can be updated
-- during pure cache operations, solving the problem of unusable CacheStats
module CacheStatsTracker 
    ( CacheStatsTracker
    , newCacheStatsTracker
    , trackCacheHit
    , trackCacheMiss  
    , getCacheStats
    ) where

import WildcardCache.Types (CacheStats(..))
import Data.IORef

-- | Mutable statistics tracker using IORef for thread safety
data CacheStatsTracker = CacheStatsTracker
    { statsRef :: IORef CacheStats
    } deriving (Eq)

-- | Create a new statistics tracker with zero initial stats
newCacheStatsTracker :: IO CacheStatsTracker
newCacheStatsTracker = do
    ref <- newIORef $ CacheStats 
        { totalPatterns = 0
        , cacheHits = 0  
        , cacheMisses = 0
        , totalLookups = 0
        , avgLookupTime = 0.0
        , memoryUsage = 0
        }
    return $ CacheStatsTracker ref

-- | Track a cache hit (when lookupPattern returns Just)
trackCacheHit :: CacheStatsTracker -> IO ()
trackCacheHit (CacheStatsTracker ref) = do
    modifyIORef ref $ \stats -> 
        let newHits = cacheHits stats + 1
            newLookups = totalLookups stats + 1
        in stats 
            { cacheHits = newHits
            , totalLookups = newLookups
            }

-- | Track a cache miss (when lookupPattern returns Nothing)  
trackCacheMiss :: CacheStatsTracker -> IO ()
trackCacheMiss (CacheStatsTracker ref) = do
    modifyIORef ref $ \stats ->
        let newMisses = cacheMisses stats + 1
            newLookups = totalLookups stats + 1
        in stats
            { cacheMisses = newMisses
            , totalLookups = newLookups
            }

-- | Get current statistics snapshot
getCacheStats :: CacheStatsTracker -> IO CacheStats
getCacheStats (CacheStatsTracker ref) = readIORef ref