-- | Factory module for creating cache instances without circular dependencies
module WildcardCacheFactory
    ( createCacheInstance
    ) where

import WildcardCache
import qualified WildcardCache.Trie as Trie

-- | Create cache instance based on implementation choice
createCacheInstance :: CacheImplementation -> CacheConfig -> IO SomeCacheImpl
createCacheInstance impl config = case impl of
    TrieCache -> do
        trieCache <- Trie.createTrieCache config
        return $ SomeCache trieCache
    _ -> error $ "Implementation not yet available: " ++ show impl