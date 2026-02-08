module Main where

import Processor
import qualified Data.Vector as V
import Data.Vector (fromList)

-- | Create a device with given memory contents
createDevice :: [Byte] -> Device
createDevice memList = Device
    { memory = fromList $ take 16 (memList ++ repeat 0)
    , r0 = 0
    , r1 = 0
    , pc = 0
    }

-- | Example 1: Simple counter program
-- Increments R0 three times then halts
counterProgram :: Device
counterProgram = createDevice [3, 3, 3, 0]  -- INC R0, INC R0, INC R0, HALT

-- | Example 2: Simple arithmetic program
-- Loads values, adds them, stores result
arithmeticProgram :: Device
arithmeticProgram = createDevice 
    [ 9, 14   -- LOAD R0, [14] (load value 5)
    , 10, 15  -- LOAD R1, [15] (load value 3)  
    , 1       -- ADD R0, R1    (R0 = 5 + 3 = 8)
    , 11, 13  -- STORE R0, [13] (store result at address 13)
    , 0       -- HALT
    , 0, 0, 0, 0, 0, 0  -- padding
    , 8       -- address 13: result storage
    , 5       -- address 14: first operand
    , 3       -- address 15: second operand
    ]

-- | Example 3: Loop program (will be detected by loop checker)
-- Infinite loop that increments R0 forever
infiniteLoopProgram :: Device
infiniteLoopProgram = createDevice 
    [ 3       -- INC R0
    , 13, 0   -- JMP [0] (jump back to start)
    ]

-- | Example 4: Output program
-- Demonstrates output instruction with different values
outputProgram :: Device
outputProgram = createDevice
    [ 8, 5    -- OUTPUT value 5 (single digit -> 1 char output)
    , 8, 12   -- OUTPUT value 12 (> 9 -> 2 chars output)
    , 8, 3    -- OUTPUT value 3 (single digit -> 1 char output)
    , 0       -- HALT
    ]

-- | Example 5: Conditional jump program
-- Uses JZ (jump if zero) to create a countdown
countdownProgram :: Device
countdownProgram = createDevice
    [ 9, 15   -- LOAD R0, [15] (load initial value 5)
    , 14, 8   -- JZ [8] (if R0 == 0, jump to HALT)
    , 5       -- DEC R0
    , 8, 0    -- OUTPUT 0 (print something each iteration)
    , 13, 1   -- JMP [1] (jump back to JZ instruction)
    , 0       -- HALT (address 8)
    , 0, 0, 0, 0, 0, 0, 0  -- padding
    , 5       -- address 15: initial countdown value
    ]

-- | Run a program and print results
runExample :: String -> Device -> IO ()
runExample name device = do
    putStrLn $ "\n=== " ++ name ++ " ==="
    putStrLn $ "Initial state: " ++ show device
    
    -- Run with timeout
    let timeoutResult = runProgram device 1000
    putStrLn $ "Run with timeout (1000 steps): " ++ show timeoutResult ++ " characters output"
    
    -- Run with loop detection
    let loopCheckResult = runProgramLoopCheck device
    putStrLn $ "Run with loop detection: " ++ show loopCheckResult ++ " characters output"
    
    -- Show final state after a few steps
    let (finalDevice, _, finished) = stepProgram $ stepProgram $ stepProgram $ initProgram device
    putStrLn $ "After 3 steps: " ++ show finalDevice ++ " (finished: " ++ show finished ++ ")"
    
    putStrLn $ "Program length: " ++ show (programLength device)

main :: IO ()
main = do
    putStrLn "Haskell 4917 Processor Implementation"
    putStrLn "====================================="
    
    runExample "Simple Counter" counterProgram
    runExample "Arithmetic Operations" arithmeticProgram  
    runExample "Infinite Loop (should be detected)" infiniteLoopProgram
    runExample "Output Instructions" outputProgram
    runExample "Countdown with Conditional Jumps" countdownProgram
    
    -- Demonstrate step-by-step execution
    putStrLn "\n=== Step-by-step execution of counter program ==="
    let device = initProgram counterProgram
    putStrLn $ "Initial: " ++ show device
    
    let (step1, out1, fin1) = stepProgram device
    putStrLn $ "Step 1: " ++ show step1 ++ " (output: " ++ show out1 ++ ", finished: " ++ show fin1 ++ ")"
    
    let (step2, out2, fin2) = stepProgram step1  
    putStrLn $ "Step 2: " ++ show step2 ++ " (output: " ++ show out2 ++ ", finished: " ++ show fin2 ++ ")"
    
    let (step3, out3, fin3) = stepProgram step2
    putStrLn $ "Step 3: " ++ show step3 ++ " (output: " ++ show out3 ++ ", finished: " ++ show fin3 ++ ")"
    
    let (step4, out4, fin4) = stepProgram step3
    putStrLn $ "Step 4: " ++ show step4 ++ " (output: " ++ show out4 ++ ", finished: " ++ show fin4 ++ ")"
    
    putStrLn "\nAll examples completed!"
