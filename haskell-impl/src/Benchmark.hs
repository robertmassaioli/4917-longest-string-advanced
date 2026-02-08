{-# LANGUAGE RecordWildCards #-}

module Benchmark
    ( runAllBenchmarks
    , benchmarkInstruction
    , benchmarkProgram
    , InstructionBenchmark(..)
    , ProgramBenchmark(..)
    ) where

import Processor
import Data.Word (Word8)
import Data.Time
import Control.DeepSeq
import Text.Printf

-- | Benchmark result for a single instruction
data InstructionBenchmark = InstructionBenchmark
    { instructionCode :: Word8
    , instructionName :: String
    , avgTimeNanos :: Double
    , iterationsRun :: Int
    , stepsPerSecond :: Double
    } deriving (Show)

-- | Benchmark result for a complete program
data ProgramBenchmark = ProgramBenchmark
    { programName :: String
    , programLength :: Int
    , totalSteps :: Int
    , totalTimeNanos :: Double
    , programStepsPerSecond :: Double
    , charactersOutput :: Int
    } deriving (Show)

-- | Number of iterations for instruction benchmarks
instructionIterations :: Int
instructionIterations = 1000000

-- | Number of iterations for program benchmarks  
programIterations :: Int
programIterations = 10000

-- | Force evaluation of a Device to ensure accurate timing
instance NFData Device where
    rnf Device{..} = rnf memory `seq` rnf r0 `seq` rnf r1 `seq` rnf pc

-- | Benchmark a single instruction by running it many times
benchmarkInstruction :: Word8 -> String -> Device -> IO InstructionBenchmark
benchmarkInstruction instrCode instrName initialDevice = do
    putStr $ "Benchmarking " ++ instrName ++ " (" ++ show instrCode ++ ")... "
    
    start <- getCurrentTime
    finalDevice <- runInstructionBench instructionIterations initialDevice
    end <- getCurrentTime
    
    let totalTime = diffUTCTime end start
        totalNanos = realToFrac totalTime * 1e9
        avgNanos = totalNanos / fromIntegral instructionIterations
        stepsPerSec = fromIntegral instructionIterations / realToFrac totalTime
        
    putStrLn $ printf "%.2f ns/op, %.0f ops/sec" avgNanos stepsPerSec
    
    return InstructionBenchmark
        { instructionCode = instrCode
        , instructionName = instrName
        , avgTimeNanos = avgNanos
        , iterationsRun = instructionIterations
        , stepsPerSecond = stepsPerSec
        }
  where
    runInstructionBench :: Int -> Device -> IO Device
    runInstructionBench 0 device = return device
    runInstructionBench n device = do
        let (newDevice, _, _) = stepProgram device
            resetDevice = newDevice { pc = 0 }  -- Reset PC to repeat instruction
        resetDevice `deepseq` runInstructionBench (n - 1) resetDevice

-- | Benchmark a complete program
benchmarkProgram :: String -> Device -> IO ProgramBenchmark
benchmarkProgram progName initialDevice = do
    putStr $ "Benchmarking program '" ++ progName ++ "'... "
    
    -- First, run once to get step count and output
    let (steps, output) = countStepsAndOutput initialDevice
        
    start <- getCurrentTime
    _ <- runProgramBench programIterations initialDevice
    end <- getCurrentTime
    
    let totalTime = diffUTCTime end start
        totalNanos = realToFrac totalTime * 1e9
        totalSteps = steps * programIterations
        stepsPerSec = fromIntegral totalSteps / realToFrac totalTime
        progLength = Processor.programLength initialDevice
        
    putStrLn $ printf "%d steps, %.0f steps/sec" steps stepsPerSec
    
    return ProgramBenchmark
        { programName = progName
        , programLength = progLength
        , totalSteps = totalSteps
        , totalTimeNanos = totalNanos
        , programStepsPerSecond = stepsPerSec
        , charactersOutput = output
        }
  where
    runProgramBench :: Int -> Device -> IO Int
    runProgramBench 0 _ = return 0
    runProgramBench n device = do
        let result = runProgram device 10000  -- Run with generous timeout
        result `deepseq` runProgramBench (n - 1) device
        
    countStepsAndOutput :: Device -> (Int, Int)
    countStepsAndOutput device = go (initProgram device) 0 0
      where
        go dev steps output
            | steps > 10000 = (steps, output)  -- Prevent infinite loops
            | otherwise = 
                let (newDev, chars, finished) = stepProgram dev
                in if finished 
                   then (steps + 1, output + chars)
                   else go newDev (steps + 1) (output + chars)

-- | Create test devices for each instruction
createInstructionTests :: [(Word8, String, Device)]
createInstructionTests =
    [ (0,  "HALT",        createDevice [0])
    , (1,  "ADD R0,R1",   (createDevice [1]) { r0 = 5, r1 = 3 })
    , (2,  "SUB R0,R1",   (createDevice [2]) { r0 = 8, r1 = 3 })
    , (3,  "INC R0",      createDevice [3])
    , (4,  "INC R1",      createDevice [4])
    , (5,  "DEC R0",      (createDevice [5]) { r0 = 5 })
    , (6,  "DEC R1",      (createDevice [6]) { r1 = 5 })
    , (7,  "NOP",         createDevice [7])
    , (8,  "OUTPUT",      createDevice [8, 5])
    , (9,  "LOAD R0",     createDevice [9, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42])
    , (10, "LOAD R1",     createDevice [10, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42])
    , (11, "STORE R0",    (createDevice [11, 15]) { r0 = 7 })
    , (12, "STORE R1",    (createDevice [12, 15]) { r1 = 7 })
    , (13, "JMP",         createDevice [13, 0])
    , (14, "JZ",          (createDevice [14, 0]) { r0 = 0 })
    , (15, "JNZ",         (createDevice [15, 0]) { r0 = 5 })
    ]

-- | Create comprehensive test programs
createProgramTests :: [(String, Device)]
createProgramTests =
    [ ("Counter Loop", createDevice 
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
        
    , ("Arithmetic Showcase", createDevice
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
        
    , ("Conditional Jumps", createDevice
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
        
    , ("All Instructions", createDevice
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

-- | Run all benchmarks and display results
runAllBenchmarks :: IO ()
runAllBenchmarks = do
    putStrLn "Haskell 4917 Processor Performance Benchmark"
    putStrLn "============================================="
    putStrLn ""
    
    -- Benchmark individual instructions
    putStrLn "Individual Instruction Benchmarks:"
    putStrLn "-----------------------------------"
    instrResults <- mapM (\(code, name, device) -> benchmarkInstruction code name device) createInstructionTests
    
    putStrLn ""
    putStrLn "Instruction Summary:"
    putStrLn $ printf "%-12s | %-8s | %-12s | %-15s" "Instruction" "Code" "Time (ns)" "Ops/sec"
    putStrLn "-------------|----------|--------------|----------------"
    mapM_ printInstructionSummary instrResults
    
    putStrLn ""
    putStrLn "Program Benchmarks:"
    putStrLn "-------------------"
    progResults <- mapM (\(name, device) -> benchmarkProgram name device) createProgramTests
    
    putStrLn ""
    putStrLn "Program Summary:"
    putStrLn $ printf "%-20s | %-8s | %-10s | %-15s | %-8s" "Program" "Length" "Steps" "Steps/sec" "Output"
    putStrLn "---------------------|----------|------------|----------------|----------"
    mapM_ printProgramSummary progResults
    
    putStrLn ""
    putStrLn "Overall Statistics:"
    putStrLn "-------------------"
    let avgInstrTime = average (map avgTimeNanos instrResults)
        maxInstrSpeed = maximum (map stepsPerSecond instrResults)
        avgProgSpeed = average (map programStepsPerSecond progResults)
        
    putStrLn $ printf "Average instruction time: %.2f ns" avgInstrTime
    putStrLn $ printf "Fastest instruction: %.0f ops/sec" maxInstrSpeed  
    putStrLn $ printf "Average program speed: %.0f steps/sec" avgProgSpeed
  where
    printInstructionSummary InstructionBenchmark{..} =
        putStrLn $ printf "%-12s | %-8d | %-12.2f | %-15.0f" 
                   instructionName instructionCode avgTimeNanos stepsPerSecond
                   
    printProgramSummary ProgramBenchmark{..} =
        putStrLn $ printf "%-20s | %-8d | %-10d | %-15.0f | %-8d"
                   programName programLength (totalSteps `div` programIterations) programStepsPerSecond charactersOutput
                   
    average :: [Double] -> Double
    average xs = sum xs / fromIntegral (length xs)