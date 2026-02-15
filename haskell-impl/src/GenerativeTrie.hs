-- | Inverted Trie data structure for efficient forbidden program filtering
-- 
-- This module provides an efficient way to represent sets of forbidden programs
-- using an inverted trie structure. Rather than storing positive patterns (what IS allowed),
-- we store negative patterns (what is NOT allowed), enabling efficient pruning during
-- candidate generation.
--
-- The trie maps program positions to sets of excluded values at each position.
-- When generating candidates, we check the trie to skip any programs that match
-- a forbidden pattern.

module GenerativeTrie
    ( GenerativeTrie
    , emptyTrie
    , insertPattern
    , isForbidden
    , isPartiallyForbidden
    , trieSize
    , trieProgramsExcluded
    , mergeTriePatterns
    , loadTrieFromDisk
    , saveTrieToDisk
    , TrieStatistics(..)
    , getTrieStatistics
    ) where

import qualified Data.Map.Strict as Map
import qualified Data.IntSet as IntSet
import Data.IntSet (IntSet)
import Data.Maybe (fromMaybe, isJust)
import qualified Data.Vector.Unboxed as Vector
import WildcardPattern (OptimizedProgram, OptimizedInstruction(..))
import qualified WildcardPattern as WP
import Data.Aeson (ToJSON(..), FromJSON(..), (.=), (.:), object, toJSON, fromJSON)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString.Lazy as BL
import Data.Word (Word8)
import Control.Monad (forM_)
import qualified Data.List as List

-- ============================================================================
-- Core Trie Data Structure
-- ============================================================================

-- | A TrieNode represents constraints at a specific memory position.
-- The IntSet contains byte values that are FORBIDDEN at this position.
-- Empty IntSet means all values (0-15) are forbidden (dead node).
-- IntSet containing all 16 values means no values are allowed (invalid state).
data TrieNode = TrieNode
    { -- Map from next position to child nodes
      children :: Map.Map Int TrieNode
      -- Set of byte values forbidden at this position (0-15)
    , forbiddenValues :: IntSet
      -- Heuristic: estimated programs blocked by this node
    , estimatedBlockedPrograms :: Integer
    } deriving (Show, Eq)

-- | The inverted trie structure for representing forbidden programs
-- Root node starts with no position constraint
newtype GenerativeTrie = GenerativeTrie TrieNode
    deriving (Show, Eq)

-- ============================================================================
-- Basic Operations
-- ============================================================================

-- | Create an empty trie (accepts all programs)
emptyTrie :: GenerativeTrie
emptyTrie = GenerativeTrie $ TrieNode Map.empty IntSet.empty 0

-- | Check if a complete program is forbidden
-- A program is forbidden if it matches any forbidden pattern in the trie
isForbidden :: [Word8] -> GenerativeTrie -> Bool
isForbidden program (GenerativeTrie root) = 
    go root program 0
  where
    -- Check recursively through trie and program
    go _ [] _ = False  -- Reached end of program, it's allowed
    go (TrieNode children forbidden _) (byte:rest) pos
        -- If this byte is in the forbidden set and we have a child node for this position,
        -- check if the rest of the program matches a forbidden pattern
        | fromIntegral byte `IntSet.member` forbidden =
            case Map.lookup (pos + 1) children of
                Nothing -> False  -- No constraint at next position, program is allowed
                Just child -> go child rest (pos + 1)  -- Continue checking with child
        | otherwise = False  -- Byte not forbidden, program is allowed

-- | Check if a partial program matches a forbidden prefix
-- Used during generation to prune branches early
isPartiallyForbidden :: [Word8] -> GenerativeTrie -> Bool
isPartiallyForbidden program (GenerativeTrie root) =
    go root program 0
  where
    go _ [] _ = False  -- Incomplete match, not definitively forbidden
    go (TrieNode children forbidden _) (byte:rest) pos =
        -- If byte is forbidden and matches exactly, continue matching
        if fromIntegral byte `IntSet.member` forbidden
        then case Map.lookup (pos + 1) children of
                Just child -> True  -- This path is forbidden, prune it
                Nothing -> False    -- No further constraint
        else False  -- Byte not forbidden, this branch is allowed

-- ============================================================================
-- Pattern Insertion
-- ============================================================================

-- | Insert a wildcard pattern into the trie
-- This marks programs matching the pattern as forbidden
insertPattern :: OptimizedProgram -> GenerativeTrie -> GenerativeTrie
insertPattern optProg (GenerativeTrie root) =
    let pattern = WP.wildcardPattern optProg
        (newRoot, _) = insertPatternIntoNode root pattern 0
    in GenerativeTrie newRoot

-- | Insert a pattern into the trie starting at a given position
-- Returns (updated node, total programs excluded by this insertion)
insertPatternIntoNode :: TrieNode -> [OptimizedInstruction] -> Int -> (TrieNode, Integer)
insertPatternIntoNode node [] _ = (node, 0)  -- End of pattern
insertPatternIntoNode node@(TrieNode children forbidden _) (instr:rest) pos =
    case instr of
        -- Wildcard means any value at this position is forbidden
        Wildcard ->
            let forbiddenBytes = IntSet.fromList [0..15]
                newForbidden = IntSet.union forbidden forbiddenBytes
                -- All values lead to child for next position
                (childNode, childExcluded) = 
                    case Map.lookup (pos + 1) children of
                        Just child -> insertPatternIntoNode child rest (pos + 1)
                        Nothing -> insertPatternIntoNode emptyTrieNode rest (pos + 1)
                newChildren = Map.insert (pos + 1) childNode children
                blockedPrograms = childExcluded * 16  -- All 16 values can lead here
            in (TrieNode newChildren newForbidden blockedPrograms, blockedPrograms)

        -- Required means exactly this value is forbidden
        Required byte ->
            let newForbidden = IntSet.insert (fromIntegral byte) forbidden
                (childNode, childExcluded) = 
                    case Map.lookup (pos + 1) children of
                        Just child -> insertPatternIntoNode child rest (pos + 1)
                        Nothing -> insertPatternIntoNode emptyTrieNode rest (pos + 1)
                newChildren = Map.insert (pos + 1) childNode children
            in (TrieNode newChildren newForbidden childExcluded, childExcluded)

        -- AnyOf means these specific values are forbidden
        AnyOf bytes ->
            let forbiddenBytes = IntSet.fromList (map fromIntegral bytes)
                newForbidden = IntSet.union forbidden forbiddenBytes
                (childNode, childExcluded) = 
                    case Map.lookup (pos + 1) children of
                        Just child -> insertPatternIntoNode child rest (pos + 1)
                        Nothing -> insertPatternIntoNode emptyTrieNode rest (pos + 1)
                newChildren = Map.insert (pos + 1) childNode children
                blockedPrograms = childExcluded * fromIntegral (length bytes)  -- Only these values lead here
            in (TrieNode newChildren newForbidden blockedPrograms, blockedPrograms)
  where
    emptyTrieNode = TrieNode Map.empty IntSet.empty 0

-- ============================================================================
-- Heuristic Scoring for Generation
-- ============================================================================

-- | Calculate heuristic score for a candidate byte value at a position
-- Higher score = more likely to lead to longer execution
-- Score based on instruction type and whether it creates loops/complex control flow
scoreByteForPosition :: Int -> Word8 -> Int
scoreByteForPosition pos byte =
    let instr = fromIntegral byte :: Int
        baseScore = case instr of
            -- Jump instructions create loops (high score)
            13 -> 30  -- JMP (unconditional jump)
            14 -> 25  -- JZ (conditional jump if R0 == 0)
            15 -> 25  -- JNZ (conditional jump if R0 != 0)
            -- Register operations (enable loops through jumps)
            1 -> 15   -- ADD
            2 -> 15   -- SUB
            3 -> 12   -- INC_R0
            4 -> 12   -- INC_R1
            5 -> 12   -- DEC_R0
            6 -> 12   -- DEC_R1
            9 -> 15   -- LOAD_R0
            10 -> 15  -- LOAD_R1
            11 -> 10  -- STORE_R0
            12 -> 10  -- STORE_R1
            -- Print instruction (generates output)
            8 -> 20   -- PRINT
            -- Other instructions
            0 -> 0    -- HALT
            7 -> 5    -- NOP
            _ -> 0
        -- Position bonus: instructions at beginning of program have lower cost
        positionBonus = max 0 (10 - pos)
    in baseScore + positionBonus

-- ============================================================================
-- Statistics and Introspection
-- ============================================================================

-- | Statistics about the trie structure
data TrieStatistics = TrieStatistics
    { trieTotalNodes :: Int
    , trieMaxDepth :: Int
    , trieProgramsBlockedEstimate :: Integer
    , trieForbiddenSetSizes :: [(Int, Int)]  -- (position, avg forbidden count)
    } deriving (Show, Eq)

-- | Get statistics about the current trie
getTrieStatistics :: GenerativeTrie -> TrieStatistics
getTrieStatistics (GenerativeTrie root) =
    let nodes = countNodes root
        depth = maxDepth root
        blocked = estimatedBlockedPrograms root
        sizesPerPosition = forbiddenSizesPerPosition root
    in TrieStatistics nodes depth blocked sizesPerPosition
  where
    countNodes (TrieNode children _ _) =
        1 + sum (map countNodes (Map.elems children))
    
    maxDepth (TrieNode children _ _)
        | Map.null children = 1
        | otherwise = 1 + maximum (map maxDepth (Map.elems children))
    
    forbiddenSizesPerPosition (TrieNode children forbidden _) =
        let currentSize = if IntSet.null forbidden then 0 else IntSet.size forbidden
            childSizes = Map.toList children >>= \(pos, child) -> forbiddenSizesPerPosition child
        in if currentSize > 0 then [(0, currentSize)] ++ childSizes else childSizes

-- | Calculate total program count excluded by patterns
-- This is a rough estimate based on trie structure
trieProgramsExcluded :: GenerativeTrie -> Integer
trieProgramsExcluded (GenerativeTrie root) = estimatedBlockedPrograms root

-- | Get rough size estimate of excluded programs
trieSize :: GenerativeTrie -> Integer
trieSize = trieProgramsExcluded

-- ============================================================================
-- Merging and Combination
-- ============================================================================

-- | Merge multiple trie patterns into one
mergeTriePatterns :: [OptimizedProgram] -> GenerativeTrie
mergeTriePatterns programs =
    foldl (\trie prog -> insertPattern prog trie) emptyTrie programs

-- ============================================================================
-- Persistence (Disk I/O)
-- ============================================================================

-- | Save trie to disk for later resumption
saveTrieToDisk :: FilePath -> GenerativeTrie -> IO ()
saveTrieToDisk path trie = BL.writeFile path (Aeson.encode trie)

-- | Load trie from disk
loadTrieFromDisk :: FilePath -> IO (Either String GenerativeTrie)
loadTrieFromDisk path = do
    contents <- BL.readFile path
    return $ case Aeson.decode contents of
        Just trie -> Right trie
        Nothing -> Left "Failed to decode trie from disk"

-- ============================================================================
-- JSON Serialization
-- ============================================================================

instance ToJSON TrieNode where
    toJSON (TrieNode children forbidden blocked) = object
        [ Key.fromString "children" .= 
            Map.fromList [(show pos, node) | (pos, node) <- Map.toList children]
        , Key.fromString "forbidden" .= IntSet.toList forbidden
        , Key.fromString "blocked" .= blocked
        ]

instance FromJSON TrieNode where
    parseJSON = Aeson.withObject "TrieNode" $ \o -> do
        childrenObj <- o .: Key.fromString "children"
        forbiddenList <- o .: Key.fromString "forbidden"
        blocked <- o .: Key.fromString "blocked"
        let children = Map.fromList 
                [(read pos, node) | (pos, node) <- Map.toList childrenObj]
        return $ TrieNode children (IntSet.fromList forbiddenList) blocked

instance ToJSON GenerativeTrie where
    toJSON (GenerativeTrie root) = toJSON root

instance FromJSON GenerativeTrie where
    parseJSON val = GenerativeTrie <$> parseJSON val
