{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ApplicativeDo #-}

module Main (main) where

import Criterion.Main
import Criterion.Types
import TrackedProcessor
import qualified Processor as P
import Control.DeepSeq (NFData(..), deepseq)
import Control.Exception (evaluate)
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Vector.Unboxed as Vector
import Options.Applicative
import Data.Semigroup ((<>))
import System.Environment (getArgs, withArgs)
import Data.List (isPrefixOf)
import Control.Monad (when)

-- | NFData instance for TrackedDevice to ensure proper benchmarking
instance NFData TrackedDevice where
    rnf device = device `seq` ()

-- =============================================================================
-- CLI OPTIONS FOR BENCHMARK PHASE SELECTION
-- =============================================================================

-- | Benchmark phase selection options
data BenchmarkPhaseOptions = BenchmarkPhaseOptions
    { selectedPhases :: [Int]
    , benchTimeLimit :: Maybe Int
    , verbose :: Bool
    , listOnly :: Bool
    } deriving (Show, Eq)

-- | Parse benchmark command line arguments
parseBenchmarkOptions :: IO BenchmarkPhaseOptions
parseBenchmarkOptions = execParser $ info (benchmarkOptionsParser <**> helper)
    ( fullDesc
   <> progDesc "TrackedProcessor Performance Benchmark Suite - Select specific phases to run"
   <> header "trackedprocessor-bench - Comprehensive performance testing" )

-- | Main benchmark options parser
benchmarkOptionsParser :: Parser BenchmarkPhaseOptions
benchmarkOptionsParser = do
    phases <- many $ option auto
        ( long "phase"
       <> short 'p'
       <> metavar "N"
       <> help "Phase number to run (1-5). Can be specified multiple times. Default: run all phases" )
    timeLimit_ <- optional $ option auto
        ( long "time-limit"
       <> short 't'
       <> metavar "SECONDS"
       <> help "Time limit per benchmark in seconds" )
    verbose_ <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    listOnly_ <- switch
        ( long "list"
       <> short 'l'
       <> help "List available phases without running benchmarks" )
    pure $ BenchmarkPhaseOptions 
        { selectedPhases = if null phases then [1,2,3,4,5] else phases
        , benchTimeLimit = timeLimit_
        , verbose = verbose_
        , listOnly = listOnly_
        }

-- | Show available phases
showAvailablePhases :: IO ()
showAvailablePhases = do
    putStrLn ""
    putStrLn "🚀 TrackedProcessor Benchmark Phases:"
    putStrLn "====================================="
    putStrLn ""
    putStrLn "Phase 1: Individual Instructions (48 benchmarks)"
    putStrLn "  - All 16 instructions (0-15) with 3 test scenarios each"
    putStrLn "  - Tests: single-step, repeated-execution, tracking-overhead"
    putStrLn ""
    putStrLn "Phase 2: Comprehensive Programs (20 benchmarks)"
    putStrLn "  - 4 complex programs with 5 test scenarios each"
    putStrLn "  - Programs: Counter Loop, Arithmetic Showcase, Conditional Jumps, All Instructions"
    putStrLn "  - Tests: full-execution, step-counting, output-measurement, memory-analysis, register-analysis"
    putStrLn ""
    putStrLn "Phase 3: TrackedProcessor Features (TBD)"
    putStrLn "  - Enhanced tracking capability benchmarks"
    putStrLn "  - Memory access patterns, register consumption analysis"
    putStrLn ""
    putStrLn "Phase 4: Performance Comparisons (TBD)" 
    putStrLn "  - TrackedProcessor vs Original Processor comparisons"
    putStrLn "  - Overhead analysis and scaling tests"
    putStrLn ""
    putStrLn "Phase 5: Legacy Compatibility (4 benchmarks)"
    putStrLn "  - Simple benchmark programs for compatibility testing"
    putStrLn ""
    putStrLn "Usage Examples:"
    putStrLn "  trackedprocessor-bench -p 1                    # Run only Phase 1"
    putStrLn "  trackedprocessor-bench -p 1 -p 2               # Run Phases 1 and 2"
    putStrLn "  trackedprocessor-bench -t 30                   # Run all with 30s time limit"
    putStrLn "  trackedprocessor-bench -p 1 -t 10 -v           # Phase 1, 10s limit, verbose"
    putStrLn ""

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
-- PHASE 2: COMPREHENSIVE PROGRAM BENCHMARKS (ported from Benchmark.hs)
-- =============================================================================

-- | Create comprehensive TrackedProcessor test programs (ported from existing benchmark)
createTrackedProgramTests :: [(String, TrackedDevice)]
createTrackedProgramTests = map createTest programSpecs
  where
    programSpecs = 
        [ ("Counter Loop", 
            [ 3        -- INC R0
            , 8, 0     -- OUTPUT 0 
            , 9, 15    -- LOAD R0, [15] (load counter limit)
            , 2        -- SUB R0, R1 (R1 starts at 0, will be incremented)
            , 14, 0    -- JZ [0] (if result is 0, jump to start)
            , 4        -- INC R1
            , 13, 1    -- JMP [1] (jump back to OUTPUT)
            , 0        -- HALT (should not reach here in normal execution)
            , 0, 0, 0, 0, 0, 0
            , 10       -- Counter limit at address 15
            ])
            
        , ("Arithmetic Showcase", 
            [ 9, 14    -- LOAD R0, [14] (load 7)
            , 10, 15   -- LOAD R1, [15] (load 3)
            , 1        -- ADD R0, R1 (7 + 3 = 10)
            , 8, 10    -- OUTPUT 10
            , 2        -- SUB R0, R1 (10 - 3 = 7)
            , 8, 7     -- OUTPUT 7
            , 5        -- DEC R0 (7 - 1 = 6)
            , 4        -- INC R1 (3 + 1 = 4)
            , 11, 13   -- STORE R0, [13] (store 6)
            , 12, 12   -- STORE R1, [12] (store 4)
            , 0        -- HALT
            , 0        -- Address 12: will store R1
            , 0        -- Address 13: will store R0
            , 7        -- Address 14: initial R0 value
            , 3        -- Address 15: initial R1 value
            ])
            
        , ("Conditional Jumps", 
            [ 9, 15    -- LOAD R0, [15] (load 5)
            , 15, 8    -- JNZ [8] (if R0 != 0, jump to DEC section)
            , 8, 0     -- OUTPUT 0 (zero case)
            , 13, 14   -- JMP [14] (jump to halt)
            , 0, 0, 0, 0, 0, 0  -- padding
            , 5        -- DEC R0 (address 8)
            , 8, 1     -- OUTPUT 1
            , 14, 0    -- JZ [0] (if R0 == 0, jump back to start)
            , 13, 8    -- JMP [8] (jump back to DEC)
            , 0        -- HALT (address 14)
            , 5        -- Address 15: initial counter value
            ])
            
        , ("All Instructions", 
            [ 3        -- INC R0 (R0 = 1)
            , 4        -- INC R1 (R1 = 1)
            , 1        -- ADD R0, R1 (R0 = 2)
            , 2        -- SUB R0, R1 (R0 = 1)
            , 5        -- DEC R0 (R0 = 0)
            , 7        -- NOP
            , 9, 15    -- LOAD R0, [15] (R0 = 8)
            , 10, 15   -- LOAD R1, [15] (R1 = 8)
            , 11, 14   -- STORE R0, [14]
            , 12, 13   -- STORE R1, [13]
            , 8, 5     -- OUTPUT 5
            , 0        -- HALT
            , 0        -- Address 13: R1 storage
            , 0        -- Address 14: R0 storage  
            , 8        -- Address 15: test value
            ])
        ]
    
    createTest (name, program) = 
        case createTrackedDevice program of
            Left err -> error $ "Failed to create TrackedDevice for " ++ name ++ ": " ++ show err
            Right device -> (name, device)

-- | Create program-level benchmarks similar to existing Benchmark.hs
createTrackedProgramBenchmarks :: [(String, TrackedDevice)] -> [Benchmark]
createTrackedProgramBenchmarks programs = map createProgBench programs
  where
    createProgBench (name, device) =
        bgroup ("Program: " ++ name)
            [ bench "full-execution" $ benchTrackedProgramExecution device
            , bench "step-counting" $ benchTrackedStepCounting device
            , bench "output-measurement" $ benchTrackedOutputMeasurement device
            , bench "memory-analysis" $ benchTrackedMemoryAnalysis device
            , bench "register-analysis" $ benchTrackedRegisterAnalysis device
            ]

-- =============================================================================
-- PHASE 2: PROGRAM-LEVEL BENCHMARK FUNCTIONS
-- =============================================================================

-- | Benchmark full program execution with step limit
benchTrackedProgramExecution :: TrackedDevice -> Benchmarkable
benchTrackedProgramExecution device = nf runTrackedProgramWithLimit device
  where
    runTrackedProgramWithLimit d = runTrackedProgram d 10000

-- | Benchmark step counting (run until completion and count steps)
benchTrackedStepCounting :: TrackedDevice -> Benchmarkable  
benchTrackedStepCounting device = nf countTrackedSteps device
  where
    countTrackedSteps d = length $ takeWhile (not . isTrackedHalted) $ iterate stepTrackedProgram d

-- | Benchmark output measurement
benchTrackedOutputMeasurement :: TrackedDevice -> Benchmarkable
benchTrackedOutputMeasurement device = nf measureTrackedOutput device
  where
    measureTrackedOutput d = 
        let finalDevice = runTrackedProgram d 10000
        in getOutput finalDevice

-- | Benchmark comprehensive memory access analysis
benchTrackedMemoryAnalysis :: TrackedDevice -> Benchmarkable
benchTrackedMemoryAnalysis device = nf analyzeTrackedMemory device
  where
    analyzeTrackedMemory d =
        let finalDevice = runTrackedProgram d 10000
        in ( getAccessedLocations finalDevice
           , getInstructionLocations finalDevice
           , getOperandLocations finalDevice
           , getMixedUsageLocations finalDevice
           , getInstructionOnlyLocations finalDevice
           , getOperandOnlyLocations finalDevice
           )

-- | Benchmark register consumption analysis
benchTrackedRegisterAnalysis :: TrackedDevice -> Benchmarkable
benchTrackedRegisterAnalysis device = nf analyzeTrackedRegisters device
  where
    analyzeTrackedRegisters d =
        let finalDevice = runTrackedProgram d 10000
        in ( getR0WasConsumed finalDevice
           , getR1WasConsumed finalDevice
           , getR0ContainsCombination finalDevice
           )

-- | Check if TrackedDevice is halted (helper function)
isTrackedHalted :: TrackedDevice -> Bool
isTrackedHalted device = 
    let currentInstruction = (memory device) Vector.! (fromIntegral (pc device))
    in currentInstruction == 0

-- =============================================================================
-- LEGACY BENCHMARK PROGRAMS (simple programs for compatibility)
-- =============================================================================

-- Simple benchmark programs for basic compatibility testing
legacyBenchmarkPrograms :: [(String, [P.Byte])]
legacyBenchmarkPrograms = 
    [ ("Simple HALT", [0])
    , ("Print and HALT", [8, 5, 0])
    , ("Increment and HALT", [3, 0])
    , ("Simple Loop", [3, 14, 0, 0])
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
    -- Parse command line arguments, extracting our custom options while preserving Criterion options
    args <- getArgs
    let (benchOptions, criterionArgs) = separateArgs args
    
    case benchOptions of
        Just opts -> do
            if listOnly opts
                then showAvailablePhases
                else do
                    when (verbose opts) $ do
                        putStrLn $ "Running phases: " ++ show (selectedPhases opts)
                        case benchTimeLimit opts of
                            Just t -> putStrLn $ "Time limit: " ++ show t ++ " seconds per benchmark"
                            Nothing -> putStrLn "No time limit specified"
                    
                    -- Run benchmarks with filtered phases and pass remaining args to Criterion
                    withArgs criterionArgs $ defaultMain (createSelectedBenchmarks (selectedPhases opts))
        Nothing -> do
            -- If parsing fails, show help and available phases
            showAvailablePhases

-- | Separate our benchmark options from Criterion arguments
separateArgs :: [String] -> (Maybe BenchmarkPhaseOptions, [String])
separateArgs args = 
    case execParserPure defaultPrefs benchmarkParserInfo args of
        Success opts -> (Just opts, filterCriterionArgs args)
        _ -> (Nothing, args)
  where
    benchmarkParserInfo = info (benchmarkOptionsParser <**> helper)
        ( fullDesc
       <> progDesc "TrackedProcessor Performance Benchmark Suite"
       <> header "trackedprocessor-bench - Comprehensive performance testing" )

-- | Filter out our custom arguments, leaving only Criterion arguments
filterCriterionArgs :: [String] -> [String]
filterCriterionArgs [] = []
filterCriterionArgs (arg:args)
    | arg `elem` ["-p", "--phase"] = filterCriterionArgs (drop 1 args)  -- Skip next arg too
    | arg `elem` ["-t", "--time-limit"] = filterCriterionArgs (drop 1 args)  -- Skip next arg too
    | arg `elem` ["-v", "--verbose", "-l", "--list"] = filterCriterionArgs args
    | any (`isPrefixOf` arg) ["--phase=", "--time-limit="] = filterCriterionArgs args
    | otherwise = arg : filterCriterionArgs args

-- | Create benchmarks for selected phases only
createSelectedBenchmarks :: [Int] -> [Benchmark]
createSelectedBenchmarks phases = 
    putStrLn ("🚀 Running TrackedProcessor Benchmark Phases: " ++ show phases) `seq`
    concat
        [ if 1 `elem` phases 
            then [bgroup "Phase 1: Individual Instructions" $ 
                    createInstructionBenchmarks createTrackedInstructionTests]
            else []
        , if 2 `elem` phases
            then [bgroup "Phase 2: Comprehensive Programs" $
                    createTrackedProgramBenchmarks createTrackedProgramTests]
            else []
        , if 3 `elem` phases
            then [bgroup "Phase 3: TrackedProcessor Features" $ 
                    createPlaceholderBenchmarks "Phase 3 - Coming Soon"]
            else []
        , if 4 `elem` phases
            then [bgroup "Phase 4: Performance Comparisons" $
                    createPlaceholderBenchmarks "Phase 4 - Coming Soon"]
            else []
        , if 5 `elem` phases
            then [bgroup "Phase 5: Legacy Compatibility" $
                    concat (map createProgramBenchmarks legacyBenchmarkPrograms)]
            else []
        ]

-- | Create placeholder benchmarks for unimplemented phases
createPlaceholderBenchmarks :: String -> [Benchmark]
createPlaceholderBenchmarks name = 
    [bench ("placeholder-" ++ name) $ nf id (42 :: Int)]