{-# LANGUAGE RecordWildCards #-}

module Commands.OptimizeDemo (runOptimizeDemoCommand) where

import TrackedProcessor
import WildcardPattern
import Text.Printf

-- | Run the optimization demo command
runOptimizeDemoCommand :: Bool -> IO ()
runOptimizeDemoCommand verbose = do
    putStrLn ""
    putStrLn "🚀 4917 Processor Optimization Demo"
    putStrLn "===================================="
    putStrLn ""
    putStrLn "This demo shows 8 example programs being analyzed and optimized"
    putStrLn "using the WildcardPattern optimization logic. Each example demonstrates"
    putStrLn "different types of optimization opportunities:"
    putStrLn ""

    mapM_ (runExample verbose) optimizationExamples

    putStrLn ""
    putStrLn "🎯 Summary:"
    putStrLn "============"
    putStrLn "The optimization engine identifies several types of patterns:"
    putStrLn "• Unused Memory    - Memory never accessed can be wildcarded"
    putStrLn "• Dead Code        - Register operations with no observable effect"
    putStrLn "• Output Grouping  - PRINT operands grouped by output length (1 vs 2 chars)"
    putStrLn "• Memory Usage     - Instruction-only, operand-only, mixed, or unused"
    putStrLn ""
    putStrLn "This dramatically reduces search space while preserving program behavior!"

-- | Example programs showcasing different optimization scenarios
optimizationExamples :: [(String, String, [Byte])]
optimizationExamples =
    [ ("Unused Memory",
       "Program with gaps - unused memory locations",
       [8, 5, 0, 0, 0, 0, 0, 0])  -- PRINT 5, HALT, rest unused

    , ("Dead Register Operations",
       "Register operations never consumed",
       [3, 4, 5, 6, 8, 7, 0])  -- INC R0, INC R1, DEC R0, DEC R1, PRINT 7, HALT

    , ("Output Length Optimization",
       "PRINT operands grouped by output length",
       [8, 15, 8, 3, 0])  -- PRINT 15 (2-char), PRINT 3 (1-char), HALT

    , ("Mixed Memory Usage",
       "Memory used as both instruction and operand",
       [8, 4, 13, 4, 0])  -- PRINT 4, JMP 4, which jumps to INC R1, HALT

    , ("Register Consumption Chain",
       "Registers manipulated then consumed",
       [3, 3, 11, 15, 8, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7])  -- INC R0, INC R0, STORE R0 [15], PRINT 10, HALT, data=7

    , ("Complex Control Flow",
       "Program with jumps and conditionals",
       [9, 15, 14, 8, 8, 5, 13, 10, 8, 7, 0, 0, 0, 0, 0, 3])  -- Load R0 [15], JZ 8, PRINT 5, JMP 10, PRINT 7, HALT, data=3

    , ("Operand-Only Memory",
       "Memory locations only used as operands",
       [8, 14, 8, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 5])  -- PRINT [14], PRINT [15], HALT, data=12,5 at 14&15

    , ("Register Combination Effects",
       "R1 used in combination operations",
       [3, 4, 1, 8, 0, 0])  -- INC R0, INC R1, ADD R0+R1, PRINT R0, HALT
    ]

-- | Run a single optimization example
runExample :: Bool -> (String, String, [Byte]) -> IO ()
runExample verbose (title, description, program) = do
    putStrLn $ "Example: " ++ title
    putStrLn $ "─────────" ++ replicate (length title) '─'
    putStrLn $ "Description: " ++ description
    putStrLn $ "Program:     " ++ show program
    putStrLn ""

    -- Create and run TrackedDevice
    case createTrackedDevice program of
        Left err -> putStrLn $ "Error creating device: " ++ show err
        Right device -> do
            -- Run the program to completion
            let finalDevice = runTrackedProgram device 1000
            -- Analyze the program
            let analysis = analyzeProgram program finalDevice
                optimized = optimizeProgram analysis

            -- Show results - always use prettyPrintOptimizedProgram for best formatting
            putStrLn $ prettyPrintOptimizedProgram optimized

            -- Show execution details
            if verbose
                then showVerboseDetails analysis
                else showCompactDetails analysis

    putStrLn $ replicate 80 '─'
    putStrLn ""

-- | Show compact execution details
showCompactDetails :: ProgramAnalysis -> IO ()
showCompactDetails analysis = do
    putStrLn $ "Output:      " ++ show (getOutput (trackedDevice analysis))

    -- Show specific optimizations found
    showOptimizationInsights analysis

-- | Show verbose execution details
showVerboseDetails :: ProgramAnalysis -> IO ()
showVerboseDetails analysis = do
    showCompactDetails analysis
    putStrLn ""
    putStrLn "Additional Analysis:"
    putStrLn $ "R0 Status:   " ++ r0ConsumptionStatus (registerAnalysis analysis)
    putStrLn $ "R1 Status:   " ++ r1ConsumptionStatus (registerAnalysis analysis)

-- | Show key insights about what optimizations were found
showOptimizationInsights :: ProgramAnalysis -> IO ()
showOptimizationInsights analysis = do
    let regAnalysis = registerAnalysis analysis
        memAnalysis = memoryAnalysis analysis
        deadR0 = deadR0Operations regAnalysis
        deadR1 = deadR1Operations regAnalysis

    when (not $ null deadR0) $
        putStrLn $ "Dead R0:     Positions " ++ show deadR0 ++ " (unused register operations)"
    when (not $ null deadR1) $
        putStrLn $ "Dead R1:     Positions " ++ show deadR1 ++ " (unused register operations)"
    when (length (unusedMemoryPositions analysis) > 0) $
        putStrLn $ "Unused Mem:  Positions " ++ show (unusedMemoryPositions analysis)


-- | Helper for conditional output
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()
