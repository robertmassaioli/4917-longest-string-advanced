-- | Generative search algorithm with trie-based filtering
--
-- This module provides lazy candidate generation that integrates with the
-- inverted trie structure to avoid generating programs that match known
-- forbidden patterns. Rather than generating all programs and filtering,
-- we generate only valid candidates on-demand.
--
-- The key innovation is checking partial programs against the trie during
-- generation, allowing us to prune entire subtrees of the search space
-- before they are fully generated.

module GenerativeSearch
    ( generateCandidates
    , generateCandidatesWithHeuristic
    , searchForLongestOutput
    , CandidateGenerationConfig(..)
    , defaultGenerationConfig
    , GenerationProgress(..)
    ) where

import qualified Data.IntSet as IntSet
import Data.Word (Word8)
import Data.List (sortOn)
import Control.Monad (guard)
import qualified Data.Map.Strict as Map
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Control.DeepSeq (deepseq)

import GenerativeTrie
import qualified TrackedProcessor
import TrackedProcessor (createTrackedDevice, runTrackedProgramLoopCheck, TrackedDevice)
import WildcardPattern (OptimizedProgram, analyzeProgram, optimizeProgram)
import qualified WildcardPattern as WP
import Processor (Device, Byte, createDevice)

-- ============================================================================
-- Configuration
-- ============================================================================

-- | Configuration for candidate generation
data CandidateGenerationConfig = CandidateGenerationConfig
    { -- Program length to generate
      targetLength :: Int
      -- Whether to use heuristic ordering
    , useHeuristics :: Bool
      -- Maximum candidates to generate (Nothing = unlimited)
    , maxCandidates :: Maybe Integer
      -- Progress reporting callback (called every N candidates or N seconds)
    , progressCallback :: Maybe (GenerationProgress -> IO ())
      -- Progress reporting frequency (iterations)
    , progressIterations :: Integer
      -- Progress reporting frequency (seconds)
    , progressSeconds :: Double
    }

-- | Default configuration
defaultGenerationConfig :: Int -> CandidateGenerationConfig
defaultGenerationConfig len = CandidateGenerationConfig
    { targetLength = len
    , useHeuristics = True
    , maxCandidates = Nothing
    , progressCallback = Nothing
    , progressIterations = 10000
    , progressSeconds = 10.0
    }

-- | Progress information during generation
data GenerationProgress = GenerationProgress
    { candidatesGenerated :: Integer
    , candidatesTested :: Integer
    , candidatesPruned :: Integer
    , bestOutputLength :: Int
    , bestProgram :: Maybe [Word8]
    , elapsedSeconds :: Double
    } deriving (Show, Eq)

-- ============================================================================
-- Core Generation Algorithm
-- ============================================================================

-- | Generate all valid candidate programs of a given length
-- Filters out programs that match patterns in the trie
generateCandidates :: Int -> GenerativeTrie -> [[Word8]]
generateCandidates len trie = 
    generateAtPosition 0 [] len trie
  where
    -- Generate programs position by position
    generateAtPosition :: Int -> [Word8] -> Int -> GenerativeTrie -> [[Word8]]
    generateAtPosition pos partial targetLen trieFilter
        -- Reached target length, emit the complete program
        | pos >= targetLen = [reverse partial]
        -- Still building the program
        | otherwise = do
            -- Try each possible byte value (0-15)
            byte <- [0..15]
            let candidate = byte : partial
            -- Check if this partial program is forbidden
            guard (not $ isPartiallyForbidden (reverse candidate) trieFilter)
            -- Recursively generate rest of program
            generateAtPosition (pos + 1) candidate targetLen trieFilter

-- | Generate candidates with heuristic ordering
-- Values more likely to produce long outputs are tried first
generateCandidatesWithHeuristic :: Int -> GenerativeTrie -> [[Word8]]
generateCandidatesWithHeuristic len trie =
    generateAtPositionHeuristic 0 [] len trie
  where
    generateAtPositionHeuristic :: Int -> [Word8] -> Int -> GenerativeTrie -> [[Word8]]
    generateAtPositionHeuristic pos partial targetLen trieFilter
        | pos >= targetLen = [reverse partial]
        | otherwise = do
            -- Sort byte values by heuristic score (descending)
            let bytesWithScores = [(byte, scoreByteForPosition pos byte) | byte <- [0..15]]
                sortedBytes = map fst $ sortOn (negate . snd) bytesWithScores
            byte <- sortedBytes
            let candidate = byte : partial
            guard (not $ isPartiallyForbidden (reverse candidate) trieFilter)
            generateAtPositionHeuristic (pos + 1) candidate targetLen trieFilter

-- ============================================================================
-- Search for Longest Output
-- ============================================================================

-- | Search for the program with the longest output with live pattern updates
-- Takes a trie of forbidden patterns and progressively generates candidates
-- When a new best program is found, adds it to the trie to exclude similar programs
-- Returns the best program found, output, progress, and final trie
searchForLongestOutput :: CandidateGenerationConfig 
                       -> GenerativeTrie 
                       -> IO (Maybe [Word8], String, GenerationProgress, GenerativeTrie)
searchForLongestOutput config initialTrie = do
    startTime <- getCurrentTime
    searchWithLiveUpdates initialTrie Nothing "" 0 0 0 0 startTime
  where
    -- Search with live pattern updates
    searchWithLiveUpdates :: GenerativeTrie
                         -> Maybe [Word8]   -- Best program so far
                         -> String          -- Best output so far
                         -> Integer         -- Candidates generated
                         -> Integer         -- Candidates tested
                         -> Integer         -- Patterns discovered
                         -> Integer         -- Candidates pruned
                         -> UTCTime         -- Start time
                         -> IO (Maybe [Word8], String, GenerationProgress, GenerativeTrie)
    searchWithLiveUpdates currentTrie bestProg bestOutput generated tested patternCount pruned startTime = do
        -- Generate candidates with current trie state
        let candidates = if useHeuristics config
                         then generateCandidatesWithHeuristic (targetLength config) currentTrie
                         else generateCandidates (targetLength config) currentTrie
        
        -- Search through candidates with live trie updates
        searchCandidates candidates currentTrie bestProg bestOutput generated tested patternCount pruned startTime
    
    searchCandidates :: [[Word8]]
                     -> GenerativeTrie          -- Current trie state
                     -> Maybe [Word8]           -- Best program so far
                     -> String                  -- Best output so far
                     -> Integer                 -- Candidates generated
                     -> Integer                 -- Candidates tested
                     -> Integer                 -- Patterns discovered
                     -> Integer                 -- Candidates pruned (unused - calculated as total - tested)
                     -> UTCTime                 -- Start time
                     -> IO (Maybe [Word8], String, GenerationProgress, GenerativeTrie)
    searchCandidates [] finalTrie bestProg bestOutput generated tested patternCount pruned startTime = do
        endTime <- getCurrentTime
        let elapsed = realToFrac $ diffUTCTime endTime startTime
            totalPossible = 16 ^ targetLength config
            actuallyPruned = totalPossible - generated  -- How many we never even generated
        let finalProgress = GenerationProgress
                { candidatesGenerated = generated
                , candidatesTested = tested
                , candidatesPruned = actuallyPruned
                , bestOutputLength = length bestOutput
                , bestProgram = bestProg
                , elapsedSeconds = elapsed
                }
        return (bestProg, bestOutput, finalProgress, finalTrie)
    
    searchCandidates (prog:rest) currentTrie bestProg bestOutput generated tested patternCount pruned startTime = do
        -- Check if we should report progress
        currentTime <- getCurrentTime
        let elapsed = realToFrac $ diffUTCTime currentTime startTime
        let shouldReportIters = generated `mod` progressIterations config == 0
        let shouldReportTime = elapsed >= progressSeconds config
        
        when (shouldReportIters || shouldReportTime) $ do
            case progressCallback config of
                Just callback -> do
                    let totalPossible = 16 ^ targetLength config
                        actuallyPruned = totalPossible - generated
                    let progress = GenerationProgress
                            { candidatesGenerated = generated
                            , candidatesTested = tested
                            , candidatesPruned = actuallyPruned
                            , bestOutputLength = length bestOutput
                            , bestProgram = bestProg
                            , elapsedSeconds = elapsed
                            }
                    callback progress
                Nothing -> return ()
        
        -- Test this candidate
        result <- runProgramWithDevice prog
        case result of
            Left _ -> 
                -- Program failed (infinite loop, etc), skip it
                searchCandidates rest currentTrie bestProg bestOutput (generated + 1) tested patternCount pruned startTime
            Right (output, device) ->
                if length output > length bestOutput
                then do
                    -- Found a better program! Generate wildcard pattern and add to trie
                    let analysis = analyzeProgram prog device
                        optimized = optimizeProgram analysis
                        updatedTrie = insertPattern optimized currentTrie
                    
                    -- Recursively search with updated trie to get fresh candidate stream
                    endTime <- getCurrentTime
                    let currentElapsed = realToFrac $ diffUTCTime endTime startTime
                        totalPossible = 16 ^ targetLength config
                        actuallyPruned = totalPossible - generated
                    let currentProgress = GenerationProgress
                            { candidatesGenerated = generated + 1
                            , candidatesTested = tested + 1
                            , candidatesPruned = actuallyPruned
                            , bestOutputLength = length output
                            , bestProgram = Just prog
                            , elapsedSeconds = currentElapsed
                            }
                    
                    -- Report the discovery
                    case progressCallback config of
                        Just callback -> callback currentProgress
                        Nothing -> return ()
                    
                    -- Continue with updated trie
                    searchWithLiveUpdates updatedTrie (Just prog) output (generated + 1) (tested + 1) (patternCount + 1) pruned startTime
                else
                    -- Not better, continue
                    searchCandidates rest currentTrie bestProg bestOutput (generated + 1) (tested + 1) patternCount pruned startTime
    
    -- Check max candidates limit
    searchCandidates allCandidates currentTrie bestProg bestOutput generated tested patternCount pruned startTime =
        case maxCandidates config of
            Just limit | generated >= limit -> do
                endTime <- getCurrentTime
                let elapsed = realToFrac $ diffUTCTime endTime startTime
                    totalPossible = 16 ^ targetLength config
                    actuallyPruned = totalPossible - generated
                let finalProgress = GenerationProgress
                        { candidatesGenerated = generated
                        , candidatesTested = tested
                        , candidatesPruned = actuallyPruned
                        , bestOutputLength = length bestOutput
                        , bestProgram = bestProg
                        , elapsedSeconds = elapsed
                        }
                return (bestProg, bestOutput, finalProgress, currentTrie)
            _ -> searchCandidates allCandidates currentTrie bestProg bestOutput generated tested patternCount pruned startTime

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- | Run a program and return its output length as a string and the device for analysis
runProgramWithDevice :: [Word8] -> IO (Either String (String, TrackedProcessor.TrackedDevice))
runProgramWithDevice program = 
    case createTrackedDevice program of
        Left err -> return $ Left (show err)
        Right device -> do
            let finalDevice = runTrackedProgramLoopCheck device
                outputLen = TrackedProcessor.getOutput finalDevice
            return $ Right (replicate outputLen 'X', finalDevice)  -- Use dummy chars, length is what matters

-- | Heuristic scoring function (imported from GenerativeTrie, re-exported for convenience)
scoreByteForPosition :: Int -> Word8 -> Int
scoreByteForPosition pos byte =
    let instr = fromIntegral byte :: Int
        baseScore = case instr of
            13 -> 30  -- JMP (unconditional jump)
            14 -> 25  -- JZ (conditional jump if R0 == 0)
            15 -> 25  -- JNZ (conditional jump if R0 != 0)
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
            8 -> 20   -- PRINT
            0 -> 0    -- HALT
            7 -> 5    -- NOP
            _ -> 0
        positionBonus = max 0 (10 - pos)
    in baseScore + positionBonus

-- | Helper to conditionally execute IO action
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()
