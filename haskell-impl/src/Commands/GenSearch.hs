{-# LANGUAGE RecordWildCards #-}

module Commands.GenSearch
    ( runGenSearchCommand
    ) where

import Data.Word (Word8)
import Data.Time.Clock (getCurrentTime)
import Text.Printf (printf)
import System.IO (hFlush, stdout)
import System.Directory (doesFileExist)

import GenerativeTrie
import GenerativeSearch
import GenerativeStats
import WildcardPattern (OptimizedProgram)

-- ============================================================================
-- Main Command Handler
-- ============================================================================

-- | Run the generative search command with inverted trie filtering
runGenSearchCommand :: Int                  -- Program length
                   -> Bool                  -- Use heuristics
                   -> Maybe FilePath        -- Trie cache file
                   -> [FilePath]            -- Wildcard pattern files to load
                   -> Bool                  -- Verbose output
                   -> IO ()
runGenSearchCommand searchLength useHeuristics maybeTrieFile patternFiles verbose = do
    when verbose $ putStrLn $ "Starting generative search for length " ++ show searchLength
    
    -- Initialize trie with wildcard patterns
    trie <- loadOrBuildTrie patternFiles maybeTrieFile verbose
    
    -- Get trie statistics for initial report
    let trieStats = getTrieStatistics trie
    startTime <- getCurrentTime
    let initialStats = emptyStatistics searchLength startTime trieStats (length patternFiles)
    
    when verbose $ printStatistics initialStats
    
    -- Create generation configuration
    let config = (defaultGenerationConfig searchLength)
            { useHeuristics = useHeuristics
            , progressCallback = Just genSearchProgressCallback
            , progressIterations = 10000
            , progressSeconds = 10.0
            }
    
    -- Run the search
    when verbose $ putStrLn "\n🔍 Starting candidate generation and evaluation..."
    putStrLn ""
    
    (bestProgram, bestOutput, finalProgress, finalTrie) <- searchForLongestOutput config trie
    
    endTime <- getCurrentTime
    let finalTrieStats = getTrieStatistics finalTrie
        -- Count patterns by looking at trie structure (nodes with forbidden values)
        patternCount = trieTotalNodes finalTrieStats - 1  -- Subtract root node
    let finalStats = (updateStatistics initialStats finalProgress endTime)
            { searchEndTime = Just endTime
            , trieStats = finalTrieStats
            , patternsInTrie = patternCount
            }
    
    -- Print final results
    putStrLn ""
    printStatistics finalStats
    
    -- Display detailed result if found
    case bestProgram of
        Just prog -> do
            putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            putStrLn "🏆 BEST PROGRAM FOUND"
            putStrLn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            putStrLn $ "Program: " ++ show prog
            putStrLn $ "Output length: " ++ show (length bestOutput) ++ " characters"
            putStrLn ""
        Nothing ->
            putStrLn "❌ No valid programs found with output."
    
    -- Save updated trie if file specified
    case maybeTrieFile of
        Just trieFile -> do
            saveTrieToDisk trieFile trie
            when verbose $ putStrLn $ "💾 Trie saved to " ++ trieFile
        Nothing -> return ()
    
    putStrLn ""

-- ============================================================================
-- Trie Loading and Building
-- ============================================================================

-- | Load existing trie or build new one from patterns
loadOrBuildTrie :: [FilePath] -> Maybe FilePath -> Bool -> IO GenerativeTrie
loadOrBuildTrie patternFiles maybeTrieFile verbose = do
    case maybeTrieFile of
        Just trieFile -> do
            -- Try to load existing trie
            fileExists <- doesFileExist trieFile
            if fileExists && null patternFiles
            then do
                when verbose $ putStrLn $ "Loading trie from " ++ trieFile
                result <- loadTrieFromDisk trieFile
                case result of
                    Right trie -> do
                        when verbose $ putStrLn "✅ Trie loaded successfully"
                        return trie
                    Left err -> do
                        when verbose $ putStrLn $ "⚠️  Failed to load trie: " ++ err
                        when verbose $ putStrLn "Building new trie from scratch..."
                        return emptyTrie
            else if not (null patternFiles)
            then do
                -- Build new trie from patterns
                when verbose $ putStrLn $ "Building trie from " ++ show (length patternFiles) ++ " pattern files"
                buildTrieFromPatternFiles patternFiles verbose
            else
                return emptyTrie
        Nothing -> 
            -- No trie file specified, optionally load from patterns
            if null patternFiles
            then return emptyTrie
            else buildTrieFromPatternFiles patternFiles verbose

-- | Build trie from wildcard pattern files
buildTrieFromPatternFiles :: [FilePath] -> Bool -> IO GenerativeTrie
buildTrieFromPatternFiles patternFiles verbose = do
    when verbose $ putStrLn "📂 Loading wildcard patterns from files..."
    
    patterns <- concat <$> mapM loadPatternFile patternFiles
    when verbose $ putStrLn $ "✅ Loaded " ++ show (length patterns) ++ " patterns"
    
    when verbose $ putStrLn "🔨 Building inverted trie..."
    let trie = mergeTriePatterns patterns
    
    when verbose $ do
        let stats = getTrieStatistics trie
        putStrLn $ "✅ Trie built successfully"
        putStrLn $ "   Nodes: " ++ show (trieTotalNodes stats)
        putStrLn $ "   Programs blocked (est.): " ++ formatLargeNumber (trieProgramsBlockedEstimate stats)
    
    return trie

-- | Load patterns from a single file (stub - implement based on your file format)
loadPatternFile :: FilePath -> IO [OptimizedProgram]
loadPatternFile _filePath = do
    -- TODO: Implement actual file loading
    -- This would read optimized programs from disk in your chosen format
    return []

-- ============================================================================
-- Progress Reporting
-- ============================================================================

-- | Progress callback for periodic reporting
genSearchProgressCallback :: GenerationProgress -> IO ()
genSearchProgressCallback progress = do
    printProgressReport progress
    hFlush stdout

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- | Helper to conditionally execute IO action
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()
