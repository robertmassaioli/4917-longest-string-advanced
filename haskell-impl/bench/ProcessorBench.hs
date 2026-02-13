{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE RecordWildCards #-}

module Main (main) where

import Criterion.Main
import Criterion.Types
import Processor
import Control.DeepSeq (NFData(..), deepseq)
import Control.Exception (evaluate)
import Options.Applicative
import Data.Semigroup ((<>))
import System.Environment (getArgs, withArgs)
import Data.List (isPrefixOf)
import Control.Monad (when, guard)
import Text.Printf

-- | NFData instance for Device to ensure proper benchmarking
instance NFData Device where
    rnf Device{..} = rnf memory `seq` rnf r0 `seq` rnf r1 `seq` rnf pc

-- | NFData instance for OutputInfo
instance NFData OutputInfo where
    rnf NoOutput = ()
    rnf OneDigit = ()
    rnf TwoDigits = ()

-- =============================================================================
-- CLI OPTIONS FOR BENCHMARK PHASE SELECTION
-- =============================================================================

-- | Benchmark phase selection options
data ProcessorBenchmarkOptions = ProcessorBenchmarkOptions
    { selectedPhases :: [Int]
    , benchTimeLimit :: Maybe Int
    , verbose :: Bool
    , listOnly :: Bool
    } deriving (Show, Eq)

-- | Parse benchmark command line arguments
parseProcessorBenchmarkOptions :: IO ProcessorBenchmarkOptions
parseProcessorBenchmarkOptions = execParser $ info (processorBenchmarkOptionsParser <**> helper)
    ( fullDesc
   <> progDesc "Original Processor Performance Benchmark Suite - Select specific phases to run"
   <> header "processor-bench - Comprehensive performance testing for original 4917 Processor" )

-- | Main benchmark options parser
processorBenchmarkOptionsParser :: Parser ProcessorBenchmarkOptions
processorBenchmarkOptionsParser = do
    phases <- many $ option auto
        ( long "phase"
       <> short 'p'
       <> metavar "N"
       <> help "Phase number to run (1-4). Can be specified multiple times. Default: run all phases" )
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
    pure $ ProcessorBenchmarkOptions 
        { selectedPhases = if null phases then [1,2,3,4] else phases
        , benchTimeLimit = timeLimit_
        , verbose = verbose_
        , listOnly = listOnly_
        }

-- | Show available phases
showAvailableProcessorPhases :: IO ()
showAvailableProcessorPhases = do
    putStrLn ""
    putStrLn "🚀 Original Processor Benchmark Phases:"
    putStrLn "========================================"
    putStrLn ""
    putStrLn "Phase 1: Individual Instructions (16 benchmarks)"
    putStrLn "  - All 16 instructions (0-15) with realistic test scenarios"
    putStrLn "  - Tests: execution-speed, repeated-operations, step-counting"
    putStrLn ""
    putStrLn "Phase 2: Comprehensive Programs (4 benchmarks)"
    putStrLn "  - 4 complex programs testing different processor capabilities"
    putStrLn "  - Programs: Counter Loop, Arithmetic Showcase, Conditional Jumps, All Instructions"
    putStrLn "  - Tests: full-execution, step-performance, output-generation"
    putStrLn ""
    putStrLn "Phase 3: Performance Analysis (4 benchmarks)"
    putStrLn "  - Statistical analysis of instruction and program performance"
    putStrLn "  - Tests: instruction-distribution, program-complexity, execution-patterns"
    putStrLn ""
    putStrLn "Phase 4: Scaling Analysis (6 benchmarks)"
    putStrLn "  - Performance characteristics across different program lengths"
    putStrLn "  - Tests: length-scaling, complexity-impact, execution-efficiency"
    putStrLn ""
    putStrLn "Usage Examples:"
    putStrLn "  processor-bench -p 1                    # Run only Phase 1"
    putStrLn "  processor-bench -p 1 -p 2               # Run Phases 1 and 2"
    putStrLn "  processor-bench -t 30                   # Run all with 30s time limit"
    putStrLn "  processor-bench -p 1 -t 10 -v           # Phase 1, 10s limit, verbose"
    putStrLn ""

-- =============================================================================
-- PHASE 1: INDIVIDUAL INSTRUCTION BENCHMARKS
-- =============================================================================

-- | Create test devices for each instruction (ported from Benchmark.hs)
createProcessorInstructionTests :: [(Int, String, Device)]
createProcessorInstructionTests = map createTest instructionSpecs
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
        , (8,  "OUTPUT",      [8, 5])    -- OUTPUT 5 (single digit)
        , (9,  "LOAD R0",     [9, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15])  -- LOAD R0, [15] where [15] = 15
        , (10, "LOAD R1",     [10, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15]) -- LOAD R1, [15] where [15] = 15
        , (11, "STORE R0",    [11, 15])  -- STORE R0, [15] (will set R0=7)
        , (12, "STORE R1",    [12, 15])  -- STORE R1, [15] (will set R1=7)
        , (13, "JMP",         [13, 0])   -- JMP [0] (jump to start)
        , (14, "JZ",          [14, 0])   -- JZ [0] (will set R0=0 for jump)
        , (15, "JNZ",         [15, 0])   -- JNZ [0] (will set R0=5 for jump)
        ]
    
    createTest (code, name, program) =
        let device = setInitialRegisters code (createDevice program)
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

-- | Create individual instruction benchmarks
createProcessorInstructionBenchmarks :: [(Int, String, Device)] -> [Benchmark]
createProcessorInstructionBenchmarks tests = map createInstrBench tests
  where
    createInstrBench (code, name, device) =
        bgroup ("Instruction " ++ show code ++ " (" ++ name ++ ")")
            [ bench "execution-speed" $ benchProcessorInstructionSpeed device
            , bench "repeated-operations" $ benchProcessorInstructionRepeated device
            , bench "step-counting" $ benchProcessorInstructionStepCount device
            ]

-- =============================================================================
-- PHASE 2: COMPREHENSIVE PROGRAM BENCHMARKS
-- =============================================================================

-- | Create comprehensive test programs (ported from Benchmark.hs)
createProcessorProgramTests :: [(String, Device)]
createProcessorProgramTests = map createTest programSpecs
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
    
    createTest (name, program) = (name, createDevice program)

-- | Create program-level benchmarks
createProcessorProgramBenchmarks :: [(String, Device)] -> [Benchmark]
createProcessorProgramBenchmarks programs = map createProgBench programs
  where
    createProgBench (name, device) =
        bgroup ("Program: " ++ name)
            [ bench "full-execution" $ benchProcessorProgramExecution device
            , bench "step-performance" $ benchProcessorProgramStepPerformance device
            , bench "output-generation" $ benchProcessorProgramOutputGeneration device
            ]

-- =============================================================================
-- BENCHMARK FUNCTIONS
-- =============================================================================

-- | Benchmark individual instruction execution speed
benchProcessorInstructionSpeed :: Device -> Benchmarkable
benchProcessorInstructionSpeed device = nf stepProgram device

-- | Benchmark repeated instruction execution
benchProcessorInstructionRepeated :: Device -> Benchmarkable
benchProcessorInstructionRepeated device = nf runRepeatedInstruction device
  where
    runRepeatedInstruction d = 
        let (stepped, _, _) = stepProgram d
            -- Reset PC to repeat the instruction
        in stepped { pc = pc d }

-- | Benchmark instruction step counting
benchProcessorInstructionStepCount :: Device -> Benchmarkable
benchProcessorInstructionStepCount device = nf countInstructionSteps device
  where
    countInstructionSteps :: Device -> Int
    countInstructionSteps d =
        let (_, _, finished) = stepProgram d
        in if finished then 1 else 0

-- | Benchmark full program execution
benchProcessorProgramExecution :: Device -> Benchmarkable
benchProcessorProgramExecution device = nf runProgramWithLimit device
  where
    runProgramWithLimit d = runProgram d 10000

-- | Benchmark program step performance
benchProcessorProgramStepPerformance :: Device -> Benchmarkable
benchProcessorProgramStepPerformance device = nf measureProgramSteps device
  where
    measureProgramSteps :: Device -> Int
    measureProgramSteps d = countStepsUntilCompletion d 0
    
    countStepsUntilCompletion :: Device -> Int -> Int
    countStepsUntilCompletion dev steps
        | steps > 10000 = steps  -- Prevent infinite loops
        | otherwise = 
            let (newDev, _, finished) = stepProgram dev
            in if finished 
               then steps + 1
               else countStepsUntilCompletion newDev (steps + 1)

-- | Benchmark program output generation
benchProcessorProgramOutputGeneration :: Device -> Benchmarkable
benchProcessorProgramOutputGeneration device = nf measureProgramOutput device
  where
    measureProgramOutput d = runProgram d 10000

-- =============================================================================
-- PHASE 3: PERFORMANCE ANALYSIS BENCHMARKS
-- =============================================================================

-- | Create performance analysis benchmarks
createProcessorPerformanceAnalysis :: [Benchmark]
createProcessorPerformanceAnalysis =
    [ bgroup "Performance Analysis"
        [ bench "instruction-distribution" $ benchInstructionDistribution
        , bench "program-complexity" $ benchProgramComplexity  
        , bench "execution-patterns" $ benchExecutionPatterns
        , bench "performance-metrics" $ benchPerformanceMetrics
        ]
    ]

benchInstructionDistribution :: Benchmarkable
benchInstructionDistribution = nf analyzeInstructionDistribution createProcessorInstructionTests
  where
    analyzeInstructionDistribution :: [(Int, String, Device)] -> Int
    analyzeInstructionDistribution tests = 
        let devices = map (\(_, _, d) -> d) tests
            steps = map (\d -> let (_, _, finished) = stepProgram d in if finished then 1 else 0) devices
        in sum steps

benchProgramComplexity :: Benchmarkable
benchProgramComplexity = nf analyzeProgramComplexity createProcessorProgramTests
  where
    analyzeProgramComplexity :: [(String, Device)] -> Int
    analyzeProgramComplexity tests =
        let devices = map snd tests
            lengths = map programLength devices
        in sum lengths

benchExecutionPatterns :: Benchmarkable
benchExecutionPatterns = nf analyzeExecutionPatterns createProcessorProgramTests
  where
    analyzeExecutionPatterns :: [(String, Device)] -> Int
    analyzeExecutionPatterns tests =
        let devices = map snd tests
            outputs = map (\d -> runProgram d 1000) devices
        in sum outputs

benchPerformanceMetrics :: Benchmarkable
benchPerformanceMetrics = nf analyzePerformanceMetrics createProcessorInstructionTests
  where
    analyzePerformanceMetrics :: [(Int, String, Device)] -> Int
    analyzePerformanceMetrics tests =
        let devices = map (\(_, _, d) -> d) tests
            pcs = map pc devices
        in sum (map fromIntegral pcs)

-- =============================================================================
-- PHASE 4: SCALING ANALYSIS BENCHMARKS
-- =============================================================================

-- | Create scaling analysis benchmarks
createProcessorScalingAnalysis :: [Benchmark]
createProcessorScalingAnalysis =
    [ bgroup "Scaling Analysis"
        [ bench "length-scaling-small" $ benchLengthScaling [1, 2, 3]
        , bench "length-scaling-medium" $ benchLengthScaling [4, 5, 6]
        , bench "complexity-impact-simple" $ benchComplexityImpact simplePrograms
        , bench "complexity-impact-complex" $ benchComplexityImpact complexPrograms
        , bench "execution-efficiency-short" $ benchExecutionEfficiency shortPrograms
        , bench "execution-efficiency-long" $ benchExecutionEfficiency longPrograms
        ]
    ]
  where
    simplePrograms = [createDevice [0], createDevice [3, 0], createDevice [8, 5, 0]]
    complexPrograms = map snd $ take 2 createProcessorProgramTests
    shortPrograms = [createDevice [0], createDevice [3, 0]]
    longPrograms = drop 2 $ map snd createProcessorProgramTests

benchLengthScaling :: [Int] -> Benchmarkable
benchLengthScaling lengths = nf analyzeLengthScaling lengths
  where
    analyzeLengthScaling :: [Int] -> Int
    analyzeLengthScaling lens =
        let programs = map (\l -> createDevice (replicate l 7 ++ [0])) lens
            outputs = map (\d -> runProgram d 1000) programs
        in sum outputs

benchComplexityImpact :: [Device] -> Benchmarkable
benchComplexityImpact devices = nf analyzeComplexityImpact devices
  where
    analyzeComplexityImpact :: [Device] -> Int
    analyzeComplexityImpact devs =
        let outputs = map (\d -> runProgram d 1000) devs
        in sum outputs

benchExecutionEfficiency :: [Device] -> Benchmarkable
benchExecutionEfficiency devices = nf analyzeExecutionEfficiency devices
  where
    analyzeExecutionEfficiency :: [Device] -> Int
    analyzeExecutionEfficiency devs =
        let lengths = map programLength devs
        in sum lengths

-- =============================================================================
-- MAIN FUNCTION AND ARGUMENT PARSING
-- =============================================================================

-- | Main benchmark suite with Criterion defaultMain for proper --match support  
main :: IO ()
main = defaultMain allProcessorBenchmarks
  where
    allProcessorBenchmarks =
        [ bgroup "Phase 1: Individual Instructions" $ 
            createProcessorInstructionBenchmarks createProcessorInstructionTests
        , bgroup "Phase 2: Comprehensive Programs" $
            createProcessorProgramBenchmarks createProcessorProgramTests  
        , bgroup "Phase 3: Performance Analysis" createProcessorPerformanceAnalysis
        , bgroup "Phase 4: Scaling Analysis" createProcessorScalingAnalysis
        ]

-- | Separate our benchmark options from Criterion arguments
separateProcessorArgs :: [String] -> (Maybe ProcessorBenchmarkOptions, [String])
separateProcessorArgs args = 
    case execParserPure defaultPrefs processorBenchmarkParserInfo args of
        Success opts -> (Just opts, filterProcessorCriterionArgs args)
        _ -> (Nothing, args)
  where
    processorBenchmarkParserInfo = info (processorBenchmarkOptionsParser <**> helper)
        ( fullDesc
       <> progDesc "Original Processor Performance Benchmark Suite"
       <> header "processor-bench - Comprehensive performance testing" )

-- | Filter out our custom arguments, leaving only Criterion arguments
filterProcessorCriterionArgs :: [String] -> [String]
filterProcessorCriterionArgs [] = []
filterProcessorCriterionArgs (arg:args)
    | arg `elem` ["-p", "--phase"] = filterProcessorCriterionArgs (drop 1 args)  -- Skip next arg too
    | arg `elem` ["-t", "--time-limit"] = filterProcessorCriterionArgs (drop 1 args)  -- Skip next arg too
    | arg `elem` ["-v", "--verbose", "-l", "--list"] = filterProcessorCriterionArgs args
    | any (`isPrefixOf` arg) ["--phase=", "--time-limit="] = filterProcessorCriterionArgs args
    | otherwise = arg : filterProcessorCriterionArgs args

-- | Create benchmarks for selected phases only
createSelectedProcessorBenchmarks :: [Int] -> [Benchmark]
createSelectedProcessorBenchmarks phases = 
    putStrLn ("🚀 Running Original Processor Benchmark Phases: " ++ show phases) `seq` do
        phase <- phases
        case phase of
            1 -> [bgroup "Phase 1: Individual Instructions" $ 
                    createProcessorInstructionBenchmarks createProcessorInstructionTests]
            2 -> [bgroup "Phase 2: Comprehensive Programs" $
                    createProcessorProgramBenchmarks createProcessorProgramTests]
            3 -> createProcessorPerformanceAnalysis
            4 -> createProcessorScalingAnalysis
            _ -> []