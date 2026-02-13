{-# LANGUAGE ScopedTypeVariables #-}
-- | Optimized search command using wildcard pattern caching
module Commands.OptimizedSearch (runOptimizedSearchCommand, OptimizedSearchOptions(..)) where

import WildcardCache
import WildcardCacheFactory (createCacheInstance)
import WildcardPattern (analyzeProgram, optimizeProgram)
import TrackedProcessor (runTrackedProgramLoopCheck, createTrackedDevice, getOutput, isHalted, Byte)
import qualified CacheStatsTracker as CST (CacheStatsTracker, newCacheStatsTracker, getCacheStats)
import Control.Monad (forM_, when)
import Data.IORef
import Text.Printf (printf)
import Data.List (maximumBy, sortBy)
import Data.Ord (comparing)

-- | Options for optimized search command
data OptimizedSearchOptions = OptimizedSearchOptions
    { optSearchLength :: Int                    -- Program length to search
    , optSearchCacheType :: String             -- Cache implementation ("trie", "vector", etc.)
    , optSearchMaxPatterns :: Maybe Int         -- Maximum patterns to cache
    , optSearchVerbose :: Bool                  -- Enable verbose output
    , optSearchCacheFile :: Maybe FilePath     -- Cache persistence file
    , optSearchFresh :: Bool                    -- Start with fresh cache
    } deriving (Show, Eq)

-- | Run the optimized search command
runOptimizedSearchCommand :: OptimizedSearchOptions -> IO ()
runOptimizedSearchCommand opts = do
    putStrLn $ "🚀 Starting optimized search for length " ++ show (optSearchLength opts) ++ " programs"
    putStrLn $ "Cache implementation: " ++ optSearchCacheType opts
    putStrLn ""

    -- Parse cache implementation
    let cacheImpl = case optSearchCacheType opts of
            "trie" -> TrieCache
            "vector" -> VectorScanCache
            "dfa" -> DFACache
            _ -> TrieCache  -- Safe default

    -- Create cache configuration
    let config = CacheConfig
            { maxPatterns = optSearchMaxPatterns opts
            , enableStats = optSearchVerbose opts
            , persistenceFile = optSearchCacheFile opts
            }

    -- Initialize cache (load from file if specified and not fresh)
    cache <- newIORef =<< if optSearchFresh opts
        then createCacheInstance cacheImpl config
        else loadOrCreateCache cacheImpl config

    -- Initialize statistics tracker
    statsTracker <- CST.newCacheStatsTracker

    -- Initialize results tracking
    results <- newIORef []

    -- Generate all programs of the specified length
    let allPrograms = generateAllPrograms (optSearchLength opts)
        totalPrograms = length allPrograms

    putStrLn $ "Total programs to evaluate: " ++ show totalPrograms
    putStrLn ""

    -- Track progress
    checkedCount <- newIORef (0 :: Int)
    skippedCount <- newIORef (0 :: Int)

    -- Process each program
    forM_ (zip [1..] allPrograms) $ \(idx :: Int, program) -> do
        currentCache <- readIORef cache

        lookupResult <- lookupInCache program currentCache statsTracker
        case lookupResult of
            Just existingOptProg -> do
                -- Skip this program - matches existing pattern
                modifyIORef skippedCount (+1)
                when (optSearchVerbose opts) $ do
                    putStrLn $ printf "SKIP [%d/%d]: %s (matches cached pattern)"
                               idx totalPrograms (show program)
            Nothing -> do
                -- New pattern - must run and analyze this program
                modifyIORef checkedCount (+1)

                when (optSearchVerbose opts) $ do
                    putStrLn $ printf "RUN  [%d/%d]: %s" idx totalPrograms (show program)

                -- Run and analyze the program
                case createTrackedDevice program of
                    Left err -> when (optSearchVerbose opts) $
                        putStrLn $ "  ERROR: " ++ show err
                    Right device -> do
                        let finalDevice = runTrackedProgramLoopCheck device
                            outputCount = getOutput finalDevice
                            analysis = analyzeProgram program finalDevice
                            optProg = optimizeProgram analysis

                        -- Cache the optimization result
                        modifyIORef cache (insertIntoCache optProg)

                        -- Track results (only if program halted AND produced output)
                        when (isHalted finalDevice && outputCount > 0) $ do
                            modifyIORef results ((optSearchLength opts, program, outputCount) :)
                            when (optSearchVerbose opts) $ do
                                putStrLn $ "  OUTPUT: " ++ show outputCount ++ " characters"

        -- Progress reporting every 1000 programs
        when (idx `mod` 10000 == 0) $ do
            checked <- readIORef checkedCount
            skipped <- readIORef skippedCount
            let reductionPercent :: Double = if idx > 0
                    then 100.0 * fromIntegral skipped / fromIntegral idx
                    else 0.0
            putStrLn $ printf "Progress: %d/%d (%.1f%%) - Checked: %d, Skipped: %d (%.1f%% reduction)"
                       idx totalPrograms ((100.0 :: Double) * fromIntegral idx / fromIntegral totalPrograms)
                       checked skipped reductionPercent

    -- Final statistics
    finalChecked <- readIORef checkedCount
    finalSkipped <- readIORef skippedCount
    finalResults <- readIORef results
    finalCache <- readIORef cache

    putStrLn ""
    putStrLn "🎯 Search Complete!"
    putStrLn "=================="

    -- Display consolidated cache statistics
    trackedStats <- CST.getCacheStats statsTracker
    let reductionPercent = (100.0 :: Double) * fromIntegral finalSkipped / fromIntegral totalPrograms
        executionPercent = (100.0 :: Double) * fromIntegral finalChecked / fromIntegral totalPrograms

    putStrLn "📊 Cache Performance:"
    putStrLn $ "  Total programs:   " ++ show totalPrograms
    putStrLn $ printf "  Programs executed: %d (%.1f%%)" finalChecked executionPercent
    putStrLn $ printf "  Cache hits:       %d (%.1f%% reduction)" finalSkipped reductionPercent
    putStrLn $ "  Unique patterns:  " ++ show (totalPatterns (extractCacheStats finalCache))
    putStrLn ""

    -- Find and display best results
    if null finalResults
        then putStrLn "No programs produced output."
        else do
            let bestProgram = maximumBy (comparing (\(_, _, output) -> output)) finalResults
                (_, prog, output) = bestProgram
            putStrLn "🏆 Best Result:"
            putStrLn $ "  Program: " ++ show prog
            putStrLn $ "  Output:  " ++ show output ++ " characters"
            putStrLn ""

            -- Show top 5 results (sorted by output count descending)
            let sortedResults = take 5 $ sortBy (comparing (negate . (\(o, _, _) -> o))) $
                    map (\(l, p, o) -> (o, p, l)) finalResults
            putStrLn "🥇 Top 5 Results:"
            forM_ (zip [1..] sortedResults) $ \(rank :: Int, (output, prog, len)) -> do
                putStrLn $ printf "  %d. %s → %d chars" rank (show prog) output

    -- Save cache if persistence file specified
    case optSearchCacheFile opts of
        Nothing -> return ()
        Just filePath -> do
            putStrLn $ "💾 Saving cache to: " ++ filePath
            -- Note: Actual save implementation would go here

-- | Load cache from file or create new one
loadOrCreateCache :: CacheImplementation -> CacheConfig -> IO SomeCacheImpl
loadOrCreateCache impl config =
    case persistenceFile config of
        Nothing -> createCacheInstance impl config
        Just filePath -> do
            putStrLn $ "📂 Attempting to load cache from: " ++ filePath
            -- For now, just create a new cache
            -- TODO: Implement actual loading logic
            createCacheInstance impl config

-- | Generate all programs of a given length
generateAllPrograms :: Int -> [[Byte]]
generateAllPrograms 0 = [[]]
generateAllPrograms n = do
    rest <- generateAllPrograms (n - 1)
    byte <- [0..15]  -- All possible 4-bit values
    return (byte : rest)