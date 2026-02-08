module Main where

import Processor
import SolveTask
import ClientResults
import PackProcessor
import BruteForceSearch
import Data.Word (Word32)
import Data.Vector.Unboxed ((!))  -- For vector indexing

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
    let initialDevice = initProgram device
        (step1Device, _, _) = stepProgram initialDevice
        (step2Device, _, _) = stepProgram step1Device
        (finalDevice, _, finished) = stepProgram step2Device
    putStrLn $ "After 3 steps: " ++ show finalDevice ++ " (finished: " ++ show finished ++ ")"

    putStrLn $ "Program length: " ++ show (programLength device)

-- | Demonstrate basic solveTask functionality (simplified)
testSolveTaskBasic :: String -> Word32 -> IO ()
testSolveTaskBasic description task = do
    putStrLn $ "\n=== Basic Test: " ++ description ++ " (Task ID: " ++ show task ++ ") ==="

    -- Show the initial program from the task
    let initialProgram = unpackHalfDevice task
    putStrLn $ "Initial program: " ++ printProgram initialProgram

    -- Create basic results structure (without intensive solving)
    let results = newClientResults task
    putStrLn $ "Created ClientResults for task: " ++ show (getTask results)
    putStrLn "ClientResults structure created successfully."

-- | Demonstrate solving a task with the solveTask function (warning: can be slow)
solveSampleTask :: String -> Word32 -> IO ()
solveSampleTask description task = do
    putStrLn $ "\n=== Solving Task: " ++ description ++ " (Task ID: " ++ show task ++ ") ==="

    -- Show the initial program from the task
    let initialProgram = unpackHalfDevice task
    putStrLn $ "Initial program: " ++ printProgram initialProgram

    -- Only solve if the initial program has non-zero first instruction
    if memory initialProgram ! 0 == 0
    then do
        putStrLn "Empty program - skipping solve (would be quick but no results to show)"
        let taskResults = solveTask task
        showClientResultsStatus taskResults
    else do
        putStrLn "Warning: This may take a while for complex programs..."
        -- Solve the task
        let taskResults = solveTask task
        putStrLn $ "Task ID: " ++ show (getTask taskResults)

        -- Show results for each program length
        putStrLn "Best results by program length:"
        mapM_ (showResultForLength taskResults) [1..8]  -- Show all lengths

        -- Show overall status
        putStrLn ""
        showClientResultsStatus taskResults
  where
    showResultForLength results len = do
        let charsPrinted = getLongestCharactersPrinted results len
            programPacked = getLongestProgram results len
        when (charsPrinted > 0) $ do
            let program = unpackDevice programPacked
            putStrLn $ "  Length " ++ show len ++ ": " ++ show charsPrinted ++ " characters, program: " ++ printProgram program

    when condition action = if condition then action else return ()

-- | Show the status and summary of ClientResults
showClientResultsStatus :: ClientResults -> IO ()
showClientResultsStatus results = do
    putStrLn "=== ClientResults Status ==="
    putStrLn $ "Task ID: " ++ show (getTask results)

    -- Count how many program lengths have results
    let resultsWithOutput = [(len, getLongestCharactersPrinted results len) | len <- [1..16], getLongestCharactersPrinted results len > 0]

    if null resultsWithOutput
    then putStrLn "No programs found that produce output."
    else do
        putStrLn $ "Found " ++ show (length resultsWithOutput) ++ " program length(s) with output:"
        mapM_ showLengthSummary resultsWithOutput

        -- Show the best overall result
        let bestResult = maximum (map snd resultsWithOutput)
            bestLengths = [len | (len, chars) <- resultsWithOutput, chars == bestResult]
        putStrLn $ "Best output: " ++ show bestResult ++ " characters (length(s): " ++ show bestLengths ++ ")"
  where
    showLengthSummary (len, chars) =
        putStrLn $ "  Length " ++ show len ++ ": " ++ show chars ++ " characters"

-- | Show packing and unpacking examples
demonstratePacking :: IO ()
demonstratePacking = do
    putStrLn "\n=== Device Packing/Unpacking Examples ==="

    -- Example with counter program
    let device = counterProgram
    putStrLn $ "Original device: " ++ printProgram device

    let packedFull = packDevice device
    putStrLn $ "Packed (64-bit): " ++ show packedFull

    let unpackedFull = unpackDevice packedFull
    putStrLn $ "Unpacked: " ++ printProgram unpackedFull

    let packedHalf = packHalfDevice device
    putStrLn $ "Half-packed (32-bit): " ++ show packedHalf

    let unpackedHalf = unpackHalfDevice packedHalf
    putStrLn $ "Half-unpacked: " ++ printProgram unpackedHalf

-- | Demonstrate brute force search for best programs
demonstrateBruteForceSearch :: IO ()
demonstrateBruteForceSearch = do
    putStrLn "\n=== Brute Force Program Search ==="
    putStrLn "Finding programs that produce the longest output..."
    
    putStr "Length 2: "
    case findLongestOutputProgram 2 of
        Nothing -> putStrLn "No programs found that produce output"
        Just result -> putStrLn $ "Program " ++ show (programBytes result) ++ 
                                 " produces " ++ show (outputLength result) ++ " characters"
    
    putStr "Length 3: "
    case findLongestOutputProgram 3 of
        Nothing -> putStrLn "No programs found that produce output"
        Just result -> putStrLn $ "Program " ++ show (programBytes result) ++ 
                                 " produces " ++ show (outputLength result) ++ " characters"
    
    putStr "Length 4: "
    case findLongestOutputProgram 4 of
        Nothing -> putStrLn "No programs found that produce output"
        Just result -> do
            putStrLn $ "Program " ++ show (programBytes result) ++ 
                      " produces " ++ show (outputLength result) ++ " characters"
            putStrLn $ "This is our length-4 example program that maximizes output!"

main :: IO ()
main = do
    putStrLn "Haskell 4917 Processor Implementation"
    putStrLn "====================================="

    -- Original processor demonstrations
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

    -- New demonstrations of solveTask functionality
    demonstratePacking

    -- Test basic solveTask functionality without intensive computation
    testSolveTaskBasic "Single instruction test" 0x00000003
    testSolveTaskBasic "Empty task test" 0x00000000
    testSolveTaskBasic "Output instruction test" 0x00000008

    -- Demonstrate actual task solving with simple examples
    solveSampleTask "Empty task (should be fast)" 0x00000000
    -- Note: Skipping non-empty tasks as they trigger intensive computation

    putStrLn "\nNote: Task solving can be computationally intensive for complex programs."
    putStrLn "The above examples use simple tasks that complete quickly."

    -- Test brute force search
    demonstrateBruteForceSearch

    putStrLn "\nAll examples completed!"
