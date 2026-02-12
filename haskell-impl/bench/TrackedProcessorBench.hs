{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Criterion.Main
import Criterion.Types
import TrackedProcessor
import qualified Processor as P
import Control.DeepSeq (NFData(..), deepseq)
import Control.Exception (evaluate)
import Data.Set (Set)
import qualified Data.Set as Set

-- | NFData instance for TrackedDevice to ensure proper benchmarking
instance NFData TrackedDevice where
    rnf device = device `seq` ()

-- =============================================================================
-- PHASE 1: INDIVIDUAL INSTRUCTION BENCHMARKS
-- =============================================================================

-- | Test devices for each of the 16 instructions in stepTrackedProgram
createTrackedInstructionTests :: [(Int, String, TrackedDevice)]
createTrackedInstructionTests = map createTest instructionSpecs
  where
    instructionSpecs = 
        [ (0,  "HALT",        [0])
        , (1,  "ADD R0,R1",   [1])  -- Will set R0=5, R1=3 for meaningful test
        , (2,  "SUB R0,R1",   [2])  -- Will set R0=8, R1=3 for meaningful test
        , (3,  "INC R0",      [3])
        , (4,  "INC R1",      [4])
        , (5,  "DEC R0",      [5])  -- Will set R0=5 for meaningful test
        , (6,  "DEC R1",      [6])  -- Will set R1=5 for meaningful test
        , (7,  "NOP",         [7])
        , (8,  "PRINT",       [8, 5])    -- PRINT 5 (single digit)
        , (9,  "LOAD R0",     [9, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42])  -- LOAD R0, [15] where [15] = 42
        , (10, "LOAD R1",     [10, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42]) -- LOAD R1, [15] where [15] = 42
        , (11, "STORE R0",    [11, 15])  -- STORE R0, [15] (will set R0=7)
        , (12, "STORE R1",    [12, 15])  -- STORE R1, [15] (will set R1=7)
        , (13, "JMP",         [13, 0])   -- JMP [0] (jump to start)
        , (14, "JZ",          [14, 0])   -- JZ [0] (will set R0=0 for jump)
        , (15, "JNZ",         [15, 0])   -- JNZ [0] (will set R0=5 for jump)
        ]
    
    createTest (code, name, program) =
        let device = case createTrackedDevice program of
                Left err -> error $ "Failed to create test device for " ++ name ++ ": " ++ show err
                Right d -> setInitialRegisters code d
        in (code, name, device)
    
    -- Set appropriate initial register values for meaningful instruction testing
    setInitialRegisters code device = case code of
        1  -> device { r0 = 5, r1 = 3 }    -- ADD: 5 + 3 = 8
        2  -> device { r0 = 8, r1 = 3 }    -- SUB: 8 - 3 = 5
        5  -> device { r0 = 5 }            -- DEC R0: 5 - 1 = 4
        6  -> device { r1 = 5 }            -- DEC R1: 5 - 1 = 4
        11 -> device { r0 = 7 }            -- STORE R0: store value 7
        12 -> device { r1 = 7 }            -- STORE R1: store value 7
        14 -> device { r0 = 0 }            -- JZ: R0=0 will take jump
        15 -> device { r0 = 5 }            -- JNZ: R0=5 will take jump
        _  -> device

-- =============================================================================
-- INSTRUCTION-SPECIFIC BENCHMARK FUNCTIONS
-- =============================================================================

-- | Benchmark a single instruction execution
benchSingleInstruction :: TrackedDevice -> Benchmarkable
benchSingleInstruction device = nf stepTrackedProgram device

-- | Benchmark instruction with register state reset (for repeated testing)
benchInstructionRepeated :: TrackedDevice -> Benchmarkable
benchInstructionRepeated initialDevice = nf runRepeatedInstruction initialDevice
  where
    runRepeatedInstruction device = 
        let steppedDevice = stepTrackedProgram device
            -- Reset PC to repeat the instruction, but keep tracking data
        in steppedDevice { pc = pc device }

-- | Benchmark instruction tracking overhead
benchInstructionTrackingOverhead :: TrackedDevice -> Benchmarkable
benchInstructionTrackingOverhead device = nf measureTrackingOverhead device
  where
    measureTrackingOverhead d = 
        let stepped = stepTrackedProgram d
        in (getAccessedLocations stepped, getInstructionLocations stepped, getOperandLocations stepped)

-- | Create individual instruction benchmarks
createInstructionBenchmarks :: [(Int, String, TrackedDevice)] -> [Benchmark]
createInstructionBenchmarks tests = map createInstrBench tests
  where
    createInstrBench (code, name, device) =
        bgroup ("Instruction " ++ show code ++ " (" ++ name ++ ")")
            [ bench "single-step" $ benchSingleInstruction device
            , bench "repeated-execution" $ benchInstructionRepeated device
            , bench "tracking-overhead" $ benchInstructionTrackingOverhead device
            ]

-- =============================================================================
-- LEGACY BENCHMARK PROGRAMS (for compatibility during migration)
-- =============================================================================

-- Benchmark programs similar to the existing benchmark
legacyBenchmarkPrograms :: [(String, [P.Byte])]
legacyBenchmarkPrograms = 
    [ ("Simple HALT", [0])
    , ("Print and HALT", [8, 5, 0])
    , ("Increment and HALT", [3, 0])
    , ("Simple Loop", [3, 14, 0, 0])
    , ("Complex Arithmetic", [3, 4, 1, 11, 0, 0])
    , ("Load and Store", [9, 6, 11, 7, 0, 0, 42])
    , ("Conditional Branch", [3, 14, 4, 8, 5, 0])
    , ("Long Program", [8, 10, 3, 4, 1, 9, 8, 11, 7, 12, 8, 0, 0, 13, 2])
    ]

-- =============================================================================
-- LEGACY BENCHMARK FUNCTIONS (for compatibility)
-- =============================================================================

-- | Create a TrackedDevice for benchmarking
createBenchDevice :: [P.Byte] -> TrackedDevice
createBenchDevice program = case createTrackedDevice program of
    Left err -> error $ "Benchmark setup error: " ++ show err
    Right device -> device

-- | Benchmark TrackedProcessor creation
benchCreation :: [P.Byte] -> Benchmarkable
benchCreation program = nf createBenchDevice program

-- | Benchmark single step execution
benchSingleStep :: TrackedDevice -> Benchmarkable 
benchSingleStep device = nf stepTrackedProgram device

-- | Benchmark full program execution
benchFullExecution :: [P.Byte] -> Benchmarkable
benchFullExecution program = nf runBenchProgram program
  where
    runBenchProgram prog = 
        let device = createBenchDevice prog
        in runTrackedProgram device 1000

-- | Benchmark memory access tracking
benchMemoryTracking :: TrackedDevice -> Benchmarkable
benchMemoryTracking device = nf getAccessedLocations device

-- | Benchmark register consumption tracking  
benchRegisterTracking :: TrackedDevice -> Benchmarkable
benchRegisterTracking device = nf (\d -> (getR0WasConsumed d, getR1WasConsumed d, getR0ContainsCombination d)) device

-- | Benchmark enhanced memory usage analysis
benchMemoryUsageAnalysis :: TrackedDevice -> Benchmarkable
benchMemoryUsageAnalysis device = nf (\d -> (getInstructionLocations d, getOperandLocations d, getMixedUsageLocations d)) device

-- | Create benchmarks for a specific program
createProgramBenchmarks :: (String, [P.Byte]) -> [Benchmark]
createProgramBenchmarks (name, program) = 
    let device = createBenchDevice program
        executedDevice = runTrackedProgram device 1000
    in [ bgroup name
           [ bench "creation" $ benchCreation program
           , bench "single-step" $ benchSingleStep device  
           , bench "full-execution" $ benchFullExecution program
           , bench "memory-tracking" $ benchMemoryTracking executedDevice
           , bench "register-tracking" $ benchRegisterTracking executedDevice
           , bench "usage-analysis" $ benchMemoryUsageAnalysis executedDevice
           ]
       ]

-- | Comparison benchmarks between Processor and TrackedProcessor
comparisonBenchmarks :: [Benchmark]
comparisonBenchmarks = 
    let testProgram = [3, 4, 1, 11, 0, 0]  -- Complex arithmetic program
        
        -- Original Processor benchmark
        benchOriginalProcessor = nf (\prog -> 
            let device = P.createDevice prog
                result = P.runProgramLoopCheck device
            in case result of
                P.ProgramTerminated count -> count
                P.InfiniteLoopDetected -> 0) testProgram
                
        -- TrackedProcessor benchmark  
        benchTrackedProcessor = nf (\prog ->
            let device = createBenchDevice prog
                result = runTrackedProgram device 1000
            in getOutput result) testProgram
            
    in [ bgroup "Processor Comparison"
           [ bench "Original Processor" benchOriginalProcessor
           , bench "TrackedProcessor" benchTrackedProcessor
           ]
       ]

-- | Instruction-specific benchmarks for enhanced tracking
instructionBenchmarks :: [Benchmark]
instructionBenchmarks =
    [ bgroup "Instruction Types"
        [ bench "Single-byte instructions" $ benchFullExecution [3, 4, 5, 6, 1, 2, 7, 0]
        , bench "Two-byte instructions" $ benchFullExecution [8, 5, 9, 8, 11, 7, 13, 0]
        , bench "Memory operations" $ benchFullExecution [9, 7, 10, 8, 11, 6, 12, 7, 0, 42, 13]
        , bench "Conditional operations" $ benchFullExecution [3, 14, 4, 15, 2, 0]
        ]
    ]

-- | Memory usage pattern benchmarks
memoryPatternBenchmarks :: [Benchmark] 
memoryPatternBenchmarks =
    [ bgroup "Memory Usage Patterns"
        [ bench "Instruction-only access" $ benchFullExecution [3, 4, 1, 0] 
        , bench "Mixed instruction/operand" $ benchFullExecution [8, 5, 9, 7, 11, 8, 0]
        , bench "Heavy operand usage" $ benchFullExecution [8, 1, 8, 2, 8, 3, 8, 4, 0]
        , bench "Complex memory access" $ benchFullExecution [9, 12, 10, 13, 11, 14, 12, 15, 0, 0, 0, 0, 1, 2, 3, 4]
        ]
    ]

-- | Enhanced tracking feature benchmarks
enhancedTrackingBenchmarks :: [Benchmark]
enhancedTrackingBenchmarks = 
    let complexDevice = runTrackedProgram (createBenchDevice [8, 5, 3, 4, 1, 9, 7, 11, 8, 12, 9, 0, 0, 42]) 1000
    in [ bgroup "Enhanced Tracking Features"
           [ bench "Instruction location tracking" $ nf getInstructionLocations complexDevice
           , bench "Operand location tracking" $ nf getOperandLocations complexDevice  
           , bench "Mixed usage detection" $ nf getMixedUsageLocations complexDevice
           , bench "Register consumption analysis" $ nf (\d -> (getR0WasConsumed d, getR1WasConsumed d)) complexDevice
           , bench "Combination tracking" $ nf getR0ContainsCombination complexDevice
           ]
       ]

-- | Scaling benchmarks for different program lengths
scalingBenchmarks :: [Benchmark]
scalingBenchmarks = 
    [ bgroup "Program Length Scaling"
        [ bench "Length 3" $ benchFullExecution [8, 5, 0]
        , bench "Length 5" $ benchFullExecution [3, 4, 1, 11, 0]
        , bench "Length 8" $ benchFullExecution [8, 5, 3, 4, 1, 11, 2, 0]  
        , bench "Length 12" $ benchFullExecution [8, 5, 3, 9, 8, 4, 10, 7, 1, 11, 9, 0]
        , bench "Length 16" $ benchFullExecution [8, 5, 3, 4, 1, 9, 8, 11, 7, 12, 9, 2, 15, 2, 8, 0]
        ]
    ]

-- | Main benchmark suite
main :: IO ()
main = do
    putStrLn "🚀 TrackedProcessor Performance Benchmark Suite"
    putStrLn "================================================"
    putStrLn ""
    putStrLn "Phase 1: Individual Instruction Benchmarks (16 instructions)"
    putStrLn "Phase 2: Program-Level Benchmarks (legacy compatibility)"
    putStrLn "Phase 3: TrackedProcessor-Specific Features"
    putStrLn "Phase 4: Performance Comparisons"
    putStrLn ""
    
    defaultMain $ 
        -- Phase 1: Individual instruction benchmarks
        [ bgroup "Phase 1: Individual Instructions" $ 
            createInstructionBenchmarks createTrackedInstructionTests
        ] ++
        -- Legacy benchmarks (to be migrated to Phase 2)
        concat (map createProgramBenchmarks legacyBenchmarkPrograms) ++
        comparisonBenchmarks ++
        instructionBenchmarks ++  
        memoryPatternBenchmarks ++
        enhancedTrackingBenchmarks ++
        scalingBenchmarks