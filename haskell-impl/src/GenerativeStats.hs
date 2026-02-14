-- | Statistics tracking and reporting for generative search
--
-- This module provides comprehensive statistics tracking for the generative
-- search algorithm, including performance metrics, trie statistics, and
-- progress reporting.

module GenerativeStats
    ( SearchStatistics(..)
    , emptyStatistics
    , updateStatistics
    , printStatistics
    , printProgressReport
    , formatDuration
    , formatLargeNumber
    , calculateSearchSpaceReduction
    ) where

import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, NominalDiffTime)
import Text.Printf (printf)
import Data.List (intercalate)
import qualified Data.IntSet as IntSet
import Data.Word (Word8)

import GenerativeTrie (GenerativeTrie, TrieStatistics(..), getTrieStatistics, trieProgramsExcluded)
import GenerativeSearch (GenerationProgress(..))
import qualified WildcardPattern as WP

-- ============================================================================
-- Statistics Data Structure
-- ============================================================================

-- | Complete statistics for a search run
data SearchStatistics = SearchStatistics
    { -- Search configuration
      searchLength :: Int
    , searchStartTime :: UTCTime
    , searchEndTime :: Maybe UTCTime
      
      -- Trie statistics
    , trieStats :: TrieStatistics
    , patternsInTrie :: Int
      
      -- Generation statistics
    , totalCandidatesGenerated :: Integer
    , totalCandidatesTested :: Integer
    , totalCandidatesPruned :: Integer
      
      -- Best result
    , bestProgramFound :: Maybe [Word8]
    , bestOutputLength :: Int
    , bestOutput :: String
      
      -- Performance metrics
    , candidatesPerSecond :: Double
    , estimatedTimeRemaining :: Maybe Double
    , searchSpaceReduction :: Double
    } deriving (Show, Eq)

-- ============================================================================
-- Statistics Operations
-- ============================================================================

-- | Create empty statistics
emptyStatistics :: Int -> UTCTime -> TrieStatistics -> Int -> SearchStatistics
emptyStatistics len startTime trieInfo patternCount = SearchStatistics
    { searchLength = len
    , searchStartTime = startTime
    , searchEndTime = Nothing
    , trieStats = trieInfo
    , patternsInTrie = patternCount
    , totalCandidatesGenerated = 0
    , totalCandidatesTested = 0
    , totalCandidatesPruned = 0
    , bestProgramFound = Nothing
    , bestOutputLength = 0
    , bestOutput = ""
    , candidatesPerSecond = 0.0
    , estimatedTimeRemaining = Nothing
    , searchSpaceReduction = 0.0
    }

-- | Update statistics with new progress information
updateStatistics :: SearchStatistics -> GenerationProgress -> UTCTime -> SearchStatistics
updateStatistics stats progress currentTime =
    let elapsed = realToFrac $ diffUTCTime currentTime (searchStartTime stats)
        rate = if elapsed > 0 
               then fromIntegral (candidatesGenerated progress) / elapsed
               else 0.0
        totalSearchSpace = 16 ^ searchLength stats
        remaining = totalSearchSpace - candidatesGenerated progress
        eta = if rate > 0 then Just (fromIntegral remaining / rate) else Nothing
        reduction = calculateSearchSpaceReduction (searchLength stats) (trieProgramsExcluded (undefined))
    in stats
        { totalCandidatesGenerated = candidatesGenerated progress
        , totalCandidatesTested = candidatesTested progress
        , totalCandidatesPruned = candidatesPruned progress
        , bestProgramFound = bestProgram progress
        , bestOutputLength = bestOutputLength progress
        , candidatesPerSecond = rate
        , estimatedTimeRemaining = eta
        , searchSpaceReduction = reduction
        }

-- ============================================================================
-- Formatting and Display
-- ============================================================================

-- | Print comprehensive statistics report
printStatistics :: SearchStatistics -> IO ()
printStatistics stats = do
    putStrLn ""
    putStrLn "╔══════════════════════════════════════════════════════════════════════════════════════╗"
    putStrLn "║                           GENERATIVE SEARCH STATISTICS                               ║"
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    
    -- Search configuration
    putStrLn $ printf "║ Program Length: %-68d ║" (searchLength stats)
    putStrLn $ printf "║ Patterns in Trie: %-66d ║" (patternsInTrie stats)
    
    -- Trie statistics
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn "║                                 TRIE STATISTICS                                      ║"
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn $ printf "║ Total Nodes: %-71d ║" (trieTotalNodes $ trieStats stats)
    putStrLn $ printf "║ Max Depth: %-73d ║" (trieMaxDepth $ trieStats stats)
    putStrLn $ printf "║ Programs Blocked (estimate): %-51s ║" 
        (formatLargeNumber $ trieProgramsBlockedEstimate $ trieStats stats)
    
    -- Generation statistics
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn "║                              GENERATION STATISTICS                                   ║"
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn $ printf "║ Candidates Generated: %-58s ║" 
        (formatLargeNumber $ totalCandidatesGenerated stats)
    putStrLn $ printf "║ Candidates Tested: %-61s ║" 
        (formatLargeNumber $ totalCandidatesTested stats)
    putStrLn $ printf "║ Candidates Pruned: %-61s ║" 
        (formatLargeNumber $ totalCandidatesPruned stats)
    
    -- Performance metrics
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn "║                              PERFORMANCE METRICS                                     ║"
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn $ printf "║ Candidates/Second: %-61s ║" 
        (formatLargeNumber $ round $ candidatesPerSecond stats)
    
    case searchEndTime stats of
        Just endTime -> do
            let elapsed = realToFrac $ diffUTCTime endTime (searchStartTime stats)
            putStrLn $ printf "║ Total Time: %-70s ║" (formatDuration elapsed)
        Nothing -> 
            putStrLn $ printf "║ Status: %-76s ║" ("In Progress" :: String)
    
    case estimatedTimeRemaining stats of
        Just eta -> 
            putStrLn $ printf "║ Estimated Time Remaining: %-54s ║" (formatDuration eta)
        Nothing -> return ()
    
    -- Search space reduction
    putStrLn $ printf "║ Search Space Reduction: %-56.2fx ║" (searchSpaceReduction stats)
    
    -- Best result
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    putStrLn "║                                  BEST RESULT                                         ║"
    putStrLn "╠══════════════════════════════════════════════════════════════════════════════════════╣"
    
    case bestProgramFound stats of
        Just prog -> do
            putStrLn $ printf "║ Best Program: %-70s ║" (show prog)
            putStrLn $ printf "║ Output Length: %-67d ║" (bestOutputLength stats)
            putStrLn $ printf "║ Output: %-78s ║" (take 78 $ bestOutput stats)
        Nothing ->
            putStrLn $ printf "║ No valid program found yet %-55s ║" ("" :: String)
    
    putStrLn "╚══════════════════════════════════════════════════════════════════════════════════════╝"
    putStrLn ""

-- | Print a concise progress report (for periodic updates)
printProgressReport :: GenerationProgress -> IO ()
printProgressReport progress = do
    let generated = formatLargeNumber (candidatesGenerated progress)
        tested = formatLargeNumber (candidatesTested progress)
        pruned = formatLargeNumber (candidatesPruned progress)
        bestLen = bestOutputLength progress
        elapsed = formatDuration (elapsedSeconds progress)
        rate = if elapsedSeconds progress > 0
               then formatLargeNumber $ round $ fromIntegral (candidatesGenerated progress) / elapsedSeconds progress
               else "0"
    
    putStrLn $ printf "[%s] Generated: %s | Tested: %s | Pruned: %s | Best: %d chars | Rate: %s/sec"
        elapsed generated tested pruned bestLen rate

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- | Format duration in human-readable form
formatDuration :: Double -> String
formatDuration seconds
    | seconds < 60 = printf "%.1fs" seconds
    | seconds < 3600 = printf "%.1fm" (seconds / 60)
    | seconds < 86400 = printf "%.1fh" (seconds / 3600)
    | otherwise = printf "%.1fd" (seconds / 86400)

-- | Format large numbers with commas for readability
formatLargeNumber :: Integer -> String
formatLargeNumber n = reverse $ intercalate "," $ chunksOf 3 $ reverse $ show n
  where
    chunksOf _ [] = []
    chunksOf k xs = take k xs : chunksOf k (drop k xs)

-- | Calculate search space reduction factor
calculateSearchSpaceReduction :: Int -> Integer -> Double
calculateSearchSpaceReduction len excluded =
    let totalSpace = 16 ^ len
        effectiveSpace = totalSpace - excluded
        reduction = if effectiveSpace > 0 
                    then fromIntegral totalSpace / fromIntegral effectiveSpace
                    else 1.0
    in reduction
