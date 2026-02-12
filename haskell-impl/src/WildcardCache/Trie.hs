-- | Trie-based wildcard pattern cache implementation
module WildcardCache.Trie
    ( TriePatternCache
    , createTrieCache
    , emptyTrieCache
    ) where

import WildcardPattern (OptimizedProgram, OptimizedInstruction(..), wildcardPattern, originalProgram)
import TrackedProcessor (Byte)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:), Key)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString.Lazy as LBS
import Control.Monad (guard)
import Data.Time (getCurrentTime, diffUTCTime, UTCTime)
import qualified Control.Exception

-- | Local type definitions (to avoid circular imports)
data CacheStats = CacheStats
    { totalPatterns :: Int
    , totalLookups :: Int
    , cacheHits :: Int
    , cacheMisses :: Int
    , avgLookupTime :: Double
    , memoryUsage :: Int
    } deriving (Show, Eq)

data CacheConfig = CacheConfig
    { maxPatterns :: Maybe Int
    , enableStats :: Bool
    , persistenceFile :: Maybe FilePath
    } deriving (Show, Eq)

data SaveError = SaveError String deriving (Show, Eq)
data LoadError = LoadError String deriving (Show, Eq)

-- | Trie node structure for wildcard pattern matching
data TrieNode = TrieNode
    { requiredEdges :: Map.Map Byte TrieNode     -- Exact value required -> continue
    , wildcardEdge :: Maybe TrieNode             -- Accept any value -> continue
    , anyOfEdges :: Map.Map (Set.Set Byte) TrieNode  -- Accept any from set -> continue  
    , leafPatterns :: [OptimizedProgram]         -- Complete patterns ending here
    } deriving (Show)

-- | Main trie cache structure
data TriePatternCache = TriePatternCache
    { trieRoot :: TrieNode
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
    , cacheStats = CacheStats 0 0 0 0 0.0 0
    , config = cfg
    , lastModified = Nothing
    }

-- | Create trie cache with configuration
createTrieCache :: CacheConfig -> IO TriePatternCache
createTrieCache cfg = return (emptyTrieCache cfg)

-- | Type class instances for the cache interface
class WildcardPatternCache cache where
    lookupPattern :: [Byte] -> cache -> Maybe OptimizedProgram
    insertPattern :: OptimizedProgram -> cache -> cache
    emptyCache :: cache
    getCacheStats :: cache -> CacheStats

class (WildcardPatternCache cache) => PersistentCache cache where
    saveCache :: FilePath -> cache -> IO (Either SaveError ())
    loadCache :: FilePath -> IO (Either LoadError cache)
    appendToCache :: FilePath -> OptimizedProgram -> cache -> IO (Either SaveError cache)

instance WildcardPatternCache TriePatternCache where
    -- | Check if raw program matches any cached wildcard pattern (NO EXECUTION!)
    lookupPattern program cache = 
        let result = matchesWildcardPattern program 0 (trieRoot cache)
            updatedStats = if enableStats (config cache)
                then (cacheStats cache) 
                    { totalLookups = totalLookups (cacheStats cache) + 1
                    , cacheHits = case result of
                        Just _ -> cacheHits (cacheStats cache) + 1
                        Nothing -> cacheHits (cacheStats cache)
                    , cacheMisses = case result of
                        Nothing -> cacheMisses (cacheStats cache) + 1
                        Just _ -> cacheMisses (cacheStats cache)
                    }
                else cacheStats cache
        in result
    
    -- | Insert a new OptimizedProgram into the cache
    insertPattern optProg cache = 
        let pattern = wildcardPattern optProg
            newRoot = insertPatternIntoTrie pattern 0 optProg (trieRoot cache)
            updatedStats = (cacheStats cache) 
                { totalPatterns = totalPatterns (cacheStats cache) + 1 }
        in cache 
            { trieRoot = newRoot
            , cacheStats = updatedStats
            }
    
    -- | Create an empty cache
    emptyCache = emptyTrieCache (CacheConfig Nothing False Nothing)
    
    -- | Get cache statistics for monitoring
    getCacheStats = cacheStats

-- | Core pattern matching function - traverse trie with program
matchesWildcardPattern :: [Byte] -> Int -> TrieNode -> Maybe OptimizedProgram
matchesWildcardPattern [] _ node = 
    -- End of program, return any complete pattern
    case leafPatterns node of
        (optProg:_) -> Just optProg
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
tryAnyOfEdges :: Byte -> [Byte] -> Int -> [(Set.Set Byte, TrieNode)] -> Maybe OptimizedProgram
tryAnyOfEdges _ _ _ [] = Nothing
tryAnyOfEdges byte rest pos ((validSet, nextNode):remaining)
    | byte `Set.member` validSet = 
        case matchesWildcardPattern rest pos nextNode of
            Just result -> Just result
            Nothing -> tryAnyOfEdges byte rest pos remaining
    | otherwise = tryAnyOfEdges byte rest pos remaining

-- | Insert wildcard pattern into trie
insertPatternIntoTrie :: [OptimizedInstruction] -> Int -> OptimizedProgram -> TrieNode -> TrieNode
insertPatternIntoTrie [] _ optProg node = 
    -- End of pattern, add to leaf patterns
    node { leafPatterns = optProg : leafPatterns node }

insertPatternIntoTrie (instr:rest) pos optProg node = case instr of
    Required byte -> 
        let nextNode = Map.findWithDefault emptyTrieNode byte (requiredEdges node)
            updatedNext = insertPatternIntoTrie rest (pos + 1) optProg nextNode
        in node { requiredEdges = Map.insert byte updatedNext (requiredEdges node) }
    
    Wildcard ->
        let nextNode = maybe emptyTrieNode id (wildcardEdge node)
            updatedNext = insertPatternIntoTrie rest (pos + 1) optProg nextNode
        in node { wildcardEdge = Just updatedNext }
        
    AnyOf validBytes ->
        let validSet = Set.fromList validBytes
            nextNode = Map.findWithDefault emptyTrieNode validSet (anyOfEdges node)
            updatedNext = insertPatternIntoTrie rest (pos + 1) optProg nextNode
        in node { anyOfEdges = Map.insert validSet updatedNext (anyOfEdges node) }

instance PersistentCache TriePatternCache where
    -- | Save cache to filesystem in JSON format
    saveCache filePath cache = do
        let jsonData = Aeson.encode cache
        result <- do
            LBS.writeFile filePath jsonData
            return $ Right ()
        return result `catch` \e -> return $ Left $ SaveError $ show e
      where
        catch = flip Control.Exception.catch
        
    -- | Load cache from filesystem
    loadCache filePath = do
        result <- do
            jsonData <- LBS.readFile filePath
            case Aeson.decode jsonData of
                Just cache -> return $ Right cache
                Nothing -> return $ Left $ LoadError "Failed to parse JSON"
        return result `catch` \e -> return $ Left $ LoadError $ show e
      where
        catch = flip Control.Exception.catch
        
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
        reqEdges <- o .: "requiredEdges"
        wildcardE <- o .: "wildcardEdge"
        anyOfList <- o .: "anyOfEdges"
        leafPats <- o .: "leafPatterns"
        let anyOfEdgesMap = Map.fromList [(Set.fromList s, n) | (s, n) <- anyOfList]
        return $ TrieNode (Map.fromList reqEdges) wildcardE anyOfEdgesMap leafPats

instance ToJSON CacheStats where
    toJSON stats = Aeson.object
        [ "totalPatterns" .= totalPatterns stats
        , "totalLookups" .= totalLookups stats  
        , "cacheHits" .= cacheHits stats
        , "cacheMisses" .= cacheMisses stats
        , "avgLookupTime" .= avgLookupTime stats
        , "memoryUsage" .= memoryUsage stats
        ]

instance FromJSON CacheStats where
    parseJSON = Aeson.withObject "CacheStats" $ \o -> CacheStats
        <$> o .: "totalPatterns"
        <*> o .: "totalLookups"
        <*> o .: "cacheHits"
        <*> o .: "cacheMisses"
        <*> o .: "avgLookupTime"
        <*> o .: "memoryUsage"

instance ToJSON CacheConfig where
    toJSON config = Aeson.object
        [ "maxPatterns" .= maxPatterns config
        , "enableStats" .= enableStats config
        , "persistenceFile" .= persistenceFile config
        ]

instance FromJSON CacheConfig where
    parseJSON = Aeson.withObject "CacheConfig" $ \o -> CacheConfig
        <$> o .: "maxPatterns"
        <*> o .: "enableStats"
        <*> o .: "persistenceFile"

instance ToJSON TriePatternCache where
    toJSON cache = Aeson.object
        [ "trieRoot" .= trieRoot cache
        , "cacheStats" .= cacheStats cache
        , "config" .= config cache
        ]

instance FromJSON TriePatternCache where
    parseJSON = Aeson.withObject "TriePatternCache" $ \o -> TriePatternCache
        <$> o .: "trieRoot"
        <*> o .: "cacheStats"
        <*> o .: "config"
        <*> pure Nothing  -- lastModified not serialized