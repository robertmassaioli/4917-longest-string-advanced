-- | Factory module for creating cache instances without circular dependencies
module WildcardCacheFactory
    ( createCacheInstance
    ) where

import WildcardCache
import qualified WildcardCache.Integration as Integration
import qualified WildcardCache.Trie as Trie

-- | Create cache instance based on implementation choice
createCacheInstance :: CacheImplementation -> CacheConfig -> IO SomeCacheImpl
createCacheInstance impl config = case impl of
    TrieCache -> do
        -- Convert to Trie-specific config and create wrapper
        let trieConfig = convertToTrieConfig config
        trieCache <- Integration.createTrieCache trieConfig
        return $ SomeCache trieCache
    _ -> error $ "Implementation not yet available: " ++ show impl
  where
    convertToTrieConfig cfg = Trie.CacheConfig
        { Trie.maxPatterns = maxPatterns cfg
        , Trie.enableStats = enableStats cfg
        , Trie.persistenceFile = persistenceFile cfg
        }