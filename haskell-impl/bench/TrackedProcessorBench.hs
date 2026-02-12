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

-- Benchmark programs similar to the existing benchmark
benchmarkPrograms :: [(String, [P.Byte])]
benchmarkPrograms = 
    [ ("Simple HALT", [0])
    , ("Print and HALT", [8, 5, 0])
    , ("Increment and HALT", [3, 0])
    , ("Simple Loop", [3, 14, 0, 0])
    , ("Complex Arithmetic", [3, 4, 1, 11, 0, 0])
    , ("Load and Store", [9, 6, 11, 7, 0, 0, 42])
    , ("Conditional Branch", [3, 14, 4, 8, 5, 0])
    , ("Long Program", [8, 10, 3, 4, 1, 9, 8, 11, 7, 12, 8, 0, 0, 13, 2])
    ]

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
            case P.createDevice prog of
                Left _ -> 0
                Right device -> P.outputLength $ fst $ P.runProgramLoopCheck device 1000) testProgram
                
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
    
    defaultMain $ 
        concat (map createProgramBenchmarks benchmarkPrograms) ++
        comparisonBenchmarks ++
        instructionBenchmarks ++  
        memoryPatternBenchmarks ++
        enhancedTrackingBenchmarks ++
        scalingBenchmarks