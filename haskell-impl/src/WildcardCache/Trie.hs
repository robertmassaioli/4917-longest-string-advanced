-- | Trie-based wildcard pattern cache implementation
module WildcardCache.Trie
    ( TriePatternCache
    , createTrieCache
    , emptyTrieCache
    ) where

import WildcardCache.Types
import WildcardPattern (OptimizedProgram, OptimizedInstruction(..), wildcardPattern)
import TrackedProcessor (Byte)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import Data.Time (UTCTime)
import qualified Control.Exception


-- | Trie node structure for wildcard pattern matching
data TrieNode = TrieNode
    { requiredEdges :: Map.Map Byte TrieNode     -- Exact value required -> continue
    , wildcardEdge :: Maybe TrieNode             -- Accept any value -> continue
    , anyOfEdges :: Map.Map (Set.Set Byte) TrieNode  -- Accept any from set -> continue  
    , leafPatterns :: [Int]                      -- Pattern IDs ending here
    } deriving (Show)

-- | Main trie cache structure
data TriePatternCache = TriePatternCache
    { trieRoot :: TrieNode
    , patternStore :: Map.Map Int OptimizedProgram  -- Pattern ID -> OptimizedProgram
    , nextPatternId :: Int                          -- Next available pattern ID
    , cacheStats :: CacheStats
    , config :: CacheConfig
    , lastModified :: Maybe UTCTime
    } deriving (Show)

-- | Create empty trie node
emptyTrieNode :: TrieNode
emptyTrieNode = TrieNode Map.empty Nothing Map.empty []

-- | Create empty trie cache
emptyTrieCache :: CacheConfig -> TriePatternCache
emptyTrieCache cfg = TriePatternCache
    { trieRoot = emptyTrieNode
    , patternStore = Map.empty
    , nextPatternId = 0
    , cacheStats = CacheStats 0 0 0 0 0.0 0
    , config = cfg
    , lastModified = Nothing
    }

-- | Create trie cache with configuration
createTrieCache :: CacheConfig -> IO TriePatternCache
createTrieCache cfg = return (emptyTrieCache cfg)


instance WildcardPatternCache TriePatternCache where
    -- | Check if raw program matches any cached wildcard pattern (NO EXECUTION!)
    lookupPattern program cache = 
        case matchesWildcardPattern program 0 (trieRoot cache) of
            Nothing -> Nothing
            Just patternId -> Map.lookup patternId (patternStore cache)
    
    -- | Insert a new OptimizedProgram into the cache
    insertPattern optProg cache = 
        let pattern = wildcardPattern optProg
            patternId = nextPatternId cache
            newRoot = insertPatternIntoTrie pattern 0 patternId (trieRoot cache)
            newStore = Map.insert patternId optProg (patternStore cache)
            updatedStats = (cacheStats cache) 
                { totalPatterns = totalPatterns (cacheStats cache) + 1 }
        in cache 
            { trieRoot = newRoot
            , patternStore = newStore
            , nextPatternId = patternId + 1
            , cacheStats = updatedStats
            }
    
    -- | Create an empty cache
    emptyCache = emptyTrieCache (CacheConfig Nothing False Nothing)
    
    -- | Get cache statistics for monitoring
    getCacheStats = cacheStats

-- | Core pattern matching function - traverse trie with program
matchesWildcardPattern :: [Byte] -> Int -> TrieNode -> Maybe Int
matchesWildcardPattern [] _ node = 
    -- End of program, return any complete pattern ID
    case leafPatterns node of
        (patternId:_) -> Just patternId
        [] -> Nothing

matchesWildcardPattern (byte:rest) pos node = 
    -- Try exact match first (fastest)
    case Map.lookup byte (requiredEdges node) of
        Just nextNode -> matchesWildcardPattern rest (pos + 1) nextNode
        Nothing -> 
            -- Try wildcard match
            case wildcardEdge node of
                Just wildcardNode -> matchesWildcardPattern rest (pos + 1) wildcardNode
                Nothing ->
                    -- Try AnyOf matches
                    tryAnyOfEdges byte rest (pos + 1) (Map.toList $ anyOfEdges node)

-- | Try matching against AnyOf edges
tryAnyOfEdges :: Byte -> [Byte] -> Int -> [(Set.Set Byte, TrieNode)] -> Maybe Int
tryAnyOfEdges _ _ _ [] = Nothing
tryAnyOfEdges byte rest pos ((validSet, nextNode):remaining)
    | byte `Set.member` validSet = 
        case matchesWildcardPattern rest pos nextNode of
            Just result -> Just result
            Nothing -> tryAnyOfEdges byte rest pos remaining
    | otherwise = tryAnyOfEdges byte rest pos remaining

-- | Insert wildcard pattern into trie
insertPatternIntoTrie :: [OptimizedInstruction] -> Int -> Int -> TrieNode -> TrieNode
insertPatternIntoTrie [] _ patternId node = 
    -- End of pattern, add pattern ID to leaf patterns
    node { leafPatterns = patternId : leafPatterns node }

insertPatternIntoTrie (instr:rest) pos patternId node = case instr of
    Required byte -> 
        let nextNode = Map.findWithDefault emptyTrieNode byte (requiredEdges node)
            updatedNext = insertPatternIntoTrie rest (pos + 1) patternId nextNode
        in node { requiredEdges = Map.insert byte updatedNext (requiredEdges node) }
    
    Wildcard ->
        let nextNode = maybe emptyTrieNode id (wildcardEdge node)
            updatedNext = insertPatternIntoTrie rest (pos + 1) patternId nextNode
        in node { wildcardEdge = Just updatedNext }
        
    AnyOf validBytes ->
        let validSet = Set.fromList validBytes
            nextNode = Map.findWithDefault emptyTrieNode validSet (anyOfEdges node)
            updatedNext = insertPatternIntoTrie rest (pos + 1) patternId nextNode
        in node { anyOfEdges = Map.insert validSet updatedNext (anyOfEdges node) }

instance PersistentCache TriePatternCache where
    -- | Save cache to filesystem in JSON format
    saveCache filePath cache = do
        (do
            writeFile filePath (show $ Aeson.toJSON cache)
            return $ Right ()) `Control.Exception.catch` 
            (\e -> return $ Left $ SaveError $ show (e :: Control.Exception.SomeException))
        
    -- | Load cache from filesystem
    loadCache filePath = do
        (do
            jsonString <- readFile filePath
            case Aeson.decode $ read jsonString of
                Just cache -> return $ Right cache
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
instance ToJSON TrieNode where
    toJSON node = Aeson.object
        [ Key.fromString "requiredEdges" .= Map.toList (requiredEdges node)
        , Key.fromString "wildcardEdge" .= wildcardEdge node
        , Key.fromString "anyOfEdges" .= map (\(s, n) -> (Set.toList s, n)) (Map.toList $ anyOfEdges node)
        , Key.fromString "leafPatterns" .= leafPatterns node
        ]

instance FromJSON TrieNode where
    parseJSON = Aeson.withObject "TrieNode" $ \o -> do
        reqEdges <- o .: Key.fromString "requiredEdges"
        wildcardE <- o .: Key.fromString "wildcardEdge"
        anyOfList <- o .: Key.fromString "anyOfEdges"
        leafPats <- o .: Key.fromString "leafPatterns"
        let anyOfEdgesMap = Map.fromList [(Set.fromList s, n) | (s, n) <- anyOfList]
        return $ TrieNode (Map.fromList reqEdges) wildcardE anyOfEdgesMap leafPats


instance ToJSON TriePatternCache where
    toJSON cache = Aeson.object
        [ Key.fromString "trieRoot" .= trieRoot cache
        , Key.fromString "patternStore" .= Map.toList (patternStore cache)
        , Key.fromString "nextPatternId" .= nextPatternId cache
        , Key.fromString "cacheStats" .= cacheStats cache
        , Key.fromString "config" .= config cache
        ]

instance FromJSON TriePatternCache where
    parseJSON = Aeson.withObject "TriePatternCache" $ \o -> TriePatternCache
        <$> o .: Key.fromString "trieRoot"
        <*> (Map.fromList <$> o .: Key.fromString "patternStore")
        <*> o .: Key.fromString "nextPatternId"
        <*> o .: Key.fromString "cacheStats"
        <*> o .: Key.fromString "config"
        <*> pure Nothing  -- lastModified not serialized