-- | Integration layer for specific cache implementations
module WildcardCache.Integration
    ( createTrieCache
    , TrieCacheWrapper(..)
    ) where

import qualified WildcardCache.Trie as Trie
import WildcardPattern (OptimizedProgram)
import TrackedProcessor (Byte)
import qualified WildcardCache as WC

-- | Wrapper for Trie implementation to bridge type differences  
data TrieCacheWrapper = TrieCacheWrapper Trie.TriePatternCache

-- Instance implementations for TrieCacheWrapper
instance WC.WildcardPatternCache TrieCacheWrapper where
    lookupPattern program (TrieCacheWrapper trie) = Trie.lookupPattern program trie
    insertPattern optProg (TrieCacheWrapper trie) = TrieCacheWrapper (Trie.insertPattern optProg trie)
    emptyCache = TrieCacheWrapper (Trie.emptyTrieCache (Trie.CacheConfig Nothing False Nothing))
    getCacheStats (TrieCacheWrapper trie) = 
        let trieStats = Trie.getCacheStats trie
        in WC.CacheStats
            { WC.totalPatterns = Trie.totalPatterns trieStats
            , WC.totalLookups = Trie.totalLookups trieStats
            , WC.cacheHits = Trie.cacheHits trieStats
            , WC.cacheMisses = Trie.cacheMisses trieStats
            , WC.avgLookupTime = Trie.avgLookupTime trieStats
            , WC.memoryUsage = Trie.memoryUsage trieStats
            }

instance WC.PersistentCache TrieCacheWrapper where
    saveCache filePath (TrieCacheWrapper trie) = do
        result <- Trie.saveCache filePath trie
        case result of
            Left (Trie.SaveError msg) -> return $ Left (WC.SaveError msg)
            Right () -> return $ Right ()
    
    loadCache filePath = do
        result <- Trie.loadCache filePath
        case result of
            Left (Trie.LoadError msg) -> return $ Left (WC.LoadError msg)
            Right trie -> return $ Right (TrieCacheWrapper trie)
    
    appendToCache filePath optProg (TrieCacheWrapper trie) = do
        result <- Trie.appendToCache filePath optProg trie
        case result of
            Left (Trie.SaveError msg) -> return $ Left (WC.SaveError msg)
            Right newTrie -> return $ Right (TrieCacheWrapper newTrie)

createTrieCache :: Trie.CacheConfig -> IO TrieCacheWrapper
createTrieCache config = do
    trieCache <- Trie.createTrieCache config
    return $ TrieCacheWrapper trieCache