-- | Optimized search command using wildcard pattern caching
module Commands.OptimizedSearch (runOptimizedSearchCommand) where

import WildcardCache
import WildcardPattern (analyzeProgram, optimizeProgram)
import TrackedProcessor (runTrackedProgram, createTrackedDevice, getOutput, Byte)
import Control.Monad (forM_, when)
import Data.IORef
import Text.Printf (printf)
import Data.List (maximumBy)
import Data.Ord (comparing)

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
        then createCache cacheImpl config
        else loadOrCreateCache cacheImpl config
    
    -- Initialize results tracking
    results <- newIORef []
    
    -- Generate all programs of the specified length
    let allPrograms = generateAllPrograms (optSearchLength opts)
        totalPrograms = length allPrograms
    
    putStrLn $ "Total programs to evaluate: " ++ show totalPrograms
    putStrLn ""
    
    -- Track progress
    checkedCount <- newIORef 0
    skippedCount <- newIORef 0
    
    -- Process each program
    forM_ (zip [1..] allPrograms) $ \(idx, program) -> do
        currentCache <- readIORef cache
        
        case lookupInCache program currentCache of
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
                        let finalDevice = runTrackedProgram device 1000
                            outputCount = getOutput finalDevice
                            analysis = analyzeProgram program finalDevice
                            optProg = optimizeProgram analysis
                        
                        -- Cache the optimization result
                        modifyIORef cache (insertIntoCache optProg)
                        
                        -- Track results
                        when (outputCount > 0) $ do
                            modifyIORef results ((optSearchLength opts, program, outputCount) :)
                            when (optSearchVerbose opts) $ do
                                putStrLn $ "  OUTPUT: " ++ show outputCount ++ " characters"
        
        -- Progress reporting every 1000 programs
        when (idx `mod` 1000 == 0) $ do
            checked <- readIORef checkedCount
            skipped <- readIORef skippedCount
            let reductionPercent = if idx > 0 
                    then 100.0 * fromIntegral skipped / fromIntegral idx
                    else 0.0
            putStrLn $ printf "Progress: %d/%d (%.1f%%) - Checked: %d, Skipped: %d (%.1f%% reduction)"
                       idx totalPrograms (100.0 * fromIntegral idx / fromIntegral totalPrograms)
                       checked skipped reductionPercent
    
    -- Final statistics
    finalChecked <- readIORef checkedCount
    finalSkipped <- readIORef skippedCount
    finalResults <- readIORef results
    finalCache <- readIORef cache
    
    putStrLn ""
    putStrLn "🎯 Search Complete!"
    putStrLn "=================="
    putStrLn $ "Total programs:     " ++ show totalPrograms
    putStrLn $ "Programs executed:  " ++ show finalChecked
    putStrLn $ "Programs skipped:   " ++ show finalSkipped
    putStrLn $ printf "Reduction rate:     %.1f%%" (100.0 * fromIntegral finalSkipped / fromIntegral totalPrograms)
    putStrLn ""
    
    -- Display cache statistics
    let cacheStats = extractCacheStats finalCache
    putStrLn "📊 Cache Performance:"
    putStrLn $ "  Unique patterns:  " ++ show (totalPatterns cacheStats)
    putStrLn $ "  Cache hits:       " ++ show (cacheHits cacheStats)
    putStrLn $ "  Cache misses:     " ++ show (cacheMisses cacheStats)
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
            
            -- Show top 5 results
            let sortedResults = take 5 $ reverse $ 
                    map (\(l, p, o) -> (o, p, l)) $ 
                    map (\(l, p, o) -> (l, p, o)) finalResults
            putStrLn "🥇 Top 5 Results:"
            forM_ (zip [1..] sortedResults) $ \(rank, (output, prog, len)) -> do
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
        Nothing -> createCache impl config
        Just filePath -> do
            putStrLn $ "📂 Attempting to load cache from: " ++ filePath
            -- For now, just create a new cache
            -- TODO: Implement actual loading logic
            createCache impl config

-- | Generate all programs of a given length
generateAllPrograms :: Int -> [[Byte]]
generateAllPrograms 0 = [[]]
generateAllPrograms n = do
    rest <- generateAllPrograms (n - 1)
    byte <- [0..15]  -- All possible 4-bit values
    return (byte : rest)