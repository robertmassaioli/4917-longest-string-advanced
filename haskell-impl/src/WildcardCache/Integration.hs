-- | Integration layer for specific cache implementations
module WildcardCache.Integration
    ( createTrieCache
    ) where

import qualified WildcardCache.Trie as Trie
import WildcardCache.Types

-- Since TriePatternCache now directly implements the shared interfaces,
-- we can just re-export it directly instead of wrapping it
createTrieCache :: CacheConfig -> IO Trie.TriePatternCache
createTrieCache config = Trie.createTrieCache config