{-# LANGUAGE RecordWildCards #-}

module ProcessorTests
    ( runAllTests
    , TestResult(..)
    , InstructionTest(..)
    , ProgramTest(..)
    ) where

import Processor
import Data.Word (Word8)
import qualified Data.Vector as V

-- | Result of a single test
data TestResult = TestResult
    { testName :: String
    , testPassed :: Bool
    , expectedResult :: String
    , actualResult :: String
    , errorMessage :: Maybe String
    } deriving (Show)

-- | Test for a single instruction
data InstructionTest = InstructionTest
    { instrName :: String
    , initialDevice :: Device
    , expectedDevice :: Device
    , expectedOutput :: Int
    , expectedFinished :: Bool
    } deriving (Show)

-- | Test for a complete program
data ProgramTest = ProgramTest
    { progName :: String
    , program :: Device
    , expectedSteps :: Int
    , expectedFinalState :: Device
    , expectedTotalOutput :: Int
    , shouldTerminate :: Bool
    } deriving (Show)

-- | Compare two devices for equality with tolerance for differences
deviceEquals :: Device -> Device -> Bool
deviceEquals Device{memory=m1, r0=r0_1, r1=r1_1, pc=pc1} Device{memory=m2, r0=r0_2, r1=r1_2, pc=pc2} =
    m1 == m2 && r0_1 == r0_2 && r1_1 == r1_2 && pc1 == pc2

-- | Run a single instruction test
runInstructionTest :: InstructionTest -> TestResult
runInstructionTest InstructionTest{..} =
    let (actualDevice, actualOutput, actualFinished) = stepProgram initialDevice
        deviceMatch = deviceEquals actualDevice expectedDevice
        outputMatch = actualOutput == expectedOutput
        finishedMatch = actualFinished == expectedFinished
        allMatch = deviceMatch && outputMatch && finishedMatch
        
        expectedStr = "Device: " ++ show expectedDevice ++ 
                     ", Output: " ++ show expectedOutput ++ 
                     ", Finished: " ++ show expectedFinished
        actualStr = "Device: " ++ show actualDevice ++ 
                   ", Output: " ++ show actualOutput ++ 
                   ", Finished: " ++ show actualFinished
        
        errorMsg = if not allMatch
                   then Just $ "Mismatches: " ++ 
                        (if not deviceMatch then "Device " else "") ++
                        (if not outputMatch then "Output " else "") ++
                        (if not finishedMatch then "Finished " else "")
                   else Nothing
    in TestResult
        { testName = instrName
        , testPassed = allMatch
        , expectedResult = expectedStr
        , actualResult = actualStr
        , errorMessage = errorMsg
        }

-- | Run a complete program test
runProgramTest :: ProgramTest -> TestResult
runProgramTest ProgramTest{..} =
    let (steps, finalDevice, totalOutput, terminated) = runProgramWithDetails program
        stepsMatch = steps == expectedSteps
        stateMatch = deviceEquals finalDevice expectedFinalState
        outputMatch = totalOutput == expectedTotalOutput
        terminatedMatch = terminated == shouldTerminate
        allMatch = stepsMatch && stateMatch && outputMatch && terminatedMatch
        
        expectedStr = "Steps: " ++ show expectedSteps ++
                     ", Final: " ++ show expectedFinalState ++
                     ", Output: " ++ show expectedTotalOutput ++
                     ", Terminated: " ++ show shouldTerminate
        actualStr = "Steps: " ++ show steps ++
                   ", Final: " ++ show finalDevice ++
                   ", Output: " ++ show totalOutput ++
                   ", Terminated: " ++ show terminated
                   
        errorMsg = if not allMatch
                   then Just $ "Mismatches: " ++ 
                        (if not stepsMatch then "Steps " else "") ++
                        (if not stateMatch then "State " else "") ++
                        (if not outputMatch then "Output " else "") ++
                        (if not terminatedMatch then "Termination " else "")
                   else Nothing
    in TestResult
        { testName = progName
        , testPassed = allMatch
        , expectedResult = expectedStr
        , actualResult = actualStr
        , errorMessage = errorMsg
        }
  where
    runProgramWithDetails :: Device -> (Int, Device, Int, Bool)
    runProgramWithDetails device = go (initProgram device) 0 0
      where
        go dev steps output
            | steps > 10000 = (steps, dev, output, False)  -- Timeout
            | otherwise = 
                let (newDev, chars, finished) = stepProgram dev
                in if finished
                   then (steps + 1, newDev, output + chars, True)
                   else go newDev (steps + 1) (output + chars)

-- | Create test cases for each instruction
createInstructionTests :: [InstructionTest]
createInstructionTests =
    [ -- HALT instruction (0)
      InstructionTest
        { instrName = "HALT - basic halt"
        , initialDevice = createDevice [0]
        , expectedDevice = (createDevice [0]) { pc = 1 }
        , expectedOutput = 0
        , expectedFinished = True
        }
        
    -- ADD R0, R1 instruction (1)
    , InstructionTest
        { instrName = "ADD - basic addition"
        , initialDevice = (createDevice [1]) { r0 = 5, r1 = 3 }
        , expectedDevice = (createDevice [1]) { r0 = 8, r1 = 3, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "ADD - overflow wrapping"
        , initialDevice = (createDevice [1]) { r0 = 15, r1 = 5 }
        , expectedDevice = (createDevice [1]) { r0 = 4, r1 = 5, pc = 1 }  -- (15 + 5) & 0x0F = 4
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- SUB R0, R1 instruction (2)
    , InstructionTest
        { instrName = "SUB - basic subtraction"
        , initialDevice = (createDevice [2]) { r0 = 8, r1 = 3 }
        , expectedDevice = (createDevice [2]) { r0 = 5, r1 = 3, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "SUB - underflow wrapping"
        , initialDevice = (createDevice [2]) { r0 = 3, r1 = 5 }
        , expectedDevice = (createDevice [2]) { r0 = 14, r1 = 5, pc = 1 }  -- (3 - 5) & 0x0F = 14
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- INC R0 instruction (3)
    , InstructionTest
        { instrName = "INC R0 - basic increment"
        , initialDevice = (createDevice [3]) { r0 = 5 }
        , expectedDevice = (createDevice [3]) { r0 = 6, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "INC R0 - overflow wrap"
        , initialDevice = (createDevice [3]) { r0 = 15 }
        , expectedDevice = (createDevice [3]) { r0 = 0, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- INC R1 instruction (4)
    , InstructionTest
        { instrName = "INC R1 - basic increment"
        , initialDevice = (createDevice [4]) { r1 = 7 }
        , expectedDevice = (createDevice [4]) { r1 = 8, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- DEC R0 instruction (5)
    , InstructionTest
        { instrName = "DEC R0 - basic decrement"
        , initialDevice = (createDevice [5]) { r0 = 5 }
        , expectedDevice = (createDevice [5]) { r0 = 4, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "DEC R0 - underflow wrap"
        , initialDevice = (createDevice [5]) { r0 = 0 }
        , expectedDevice = (createDevice [5]) { r0 = 15, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- DEC R1 instruction (6)
    , InstructionTest
        { instrName = "DEC R1 - basic decrement"
        , initialDevice = (createDevice [6]) { r1 = 9 }
        , expectedDevice = (createDevice [6]) { r1 = 8, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- NOP instruction (7)
    , InstructionTest
        { instrName = "NOP - no operation"
        , initialDevice = (createDevice [7]) { r0 = 5, r1 = 3 }
        , expectedDevice = (createDevice [7]) { r0 = 5, r1 = 3, pc = 1 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- OUTPUT instruction (8)
    , InstructionTest
        { instrName = "OUTPUT - single digit"
        , initialDevice = createDevice [8, 5]
        , expectedDevice = (createDevice [8, 5]) { pc = 2 }
        , expectedOutput = 1  -- Single digit outputs 1 character
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "OUTPUT - double digit"
        , initialDevice = createDevice [8, 12]
        , expectedDevice = (createDevice [8, 12]) { pc = 2 }
        , expectedOutput = 2  -- Double digit outputs 2 characters
        , expectedFinished = False
        }
        
    -- LOAD R0, [addr] instruction (9)
    , InstructionTest
        { instrName = "LOAD R0 - basic load"
        , initialDevice = createDevice [9, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42]
        , expectedDevice = (createDevice [9, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42]) { r0 = 42, pc = 2 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- LOAD R1, [addr] instruction (10)
    , InstructionTest
        { instrName = "LOAD R1 - basic load"
        , initialDevice = createDevice [10, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 37, 0]
        , expectedDevice = (createDevice [10, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 37, 0]) { r1 = 37, pc = 2 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- STORE R0, [addr] instruction (11)
    , InstructionTest
        { instrName = "STORE R0 - basic store"
        , initialDevice = (createDevice [11, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) { r0 = 11 }
        , expectedDevice = (createDevice [11, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11]) { r0 = 11, pc = 2 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- STORE R1, [addr] instruction (12)
    , InstructionTest
        { instrName = "STORE R1 - basic store"
        , initialDevice = (createDevice [12, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) { r1 = 9 }
        , expectedDevice = (createDevice [12, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0]) { r1 = 9, pc = 2 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- JMP [addr] instruction (13)
    , InstructionTest
        { instrName = "JMP - unconditional jump"
        , initialDevice = createDevice [13, 5, 0, 0, 0, 0]
        , expectedDevice = (createDevice [13, 5, 0, 0, 0, 0]) { pc = 5 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- JZ [addr] instruction (14)
    , InstructionTest
        { instrName = "JZ - jump when zero"
        , initialDevice = (createDevice [14, 8, 0, 0, 0, 0, 0, 0, 0]) { r0 = 0 }
        , expectedDevice = (createDevice [14, 8, 0, 0, 0, 0, 0, 0, 0]) { r0 = 0, pc = 8 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "JZ - no jump when non-zero"
        , initialDevice = (createDevice [14, 8, 0, 0, 0, 0, 0, 0, 0]) { r0 = 5 }
        , expectedDevice = (createDevice [14, 8, 0, 0, 0, 0, 0, 0, 0]) { r0 = 5, pc = 2 }
        , expectedOutput = 0
        , expectedFinished = False
        }
        
    -- JNZ [addr] instruction (15)
    , InstructionTest
        { instrName = "JNZ - jump when non-zero"
        , initialDevice = (createDevice [15, 7, 0, 0, 0, 0, 0, 0]) { r0 = 3 }
        , expectedDevice = (createDevice [15, 7, 0, 0, 0, 0, 0, 0]) { r0 = 3, pc = 7 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    , InstructionTest
        { instrName = "JNZ - no jump when zero"
        , initialDevice = (createDevice [15, 7, 0, 0, 0, 0, 0, 0]) { r0 = 0 }
        , expectedDevice = (createDevice [15, 7, 0, 0, 0, 0, 0, 0]) { r0 = 0, pc = 2 }
        , expectedOutput = 0
        , expectedFinished = False
        }
    ]

-- | Create test cases for complete programs
createProgramTests :: [ProgramTest]
createProgramTests =
    [ -- Simple counter program
      ProgramTest
        { progName = "Simple Counter"
        , program = createDevice [3, 3, 3, 0]  -- INC R0, INC R0, INC R0, HALT
        , expectedSteps = 4
        , expectedFinalState = (createDevice [3, 3, 3, 0]) { r0 = 3, pc = 4 }
        , expectedTotalOutput = 0
        , shouldTerminate = True
        }
        
    -- Output program
    , ProgramTest
        { progName = "Output Program"
        , program = createDevice [8, 5, 8, 12, 0]  -- OUTPUT 5, OUTPUT 12, HALT
        , expectedSteps = 3
        , expectedFinalState = (createDevice [8, 5, 8, 12, 0]) { pc = 5 }
        , expectedTotalOutput = 3  -- 5 = 1 char, 12 = 2 chars
        , shouldTerminate = True
        }
        
    -- Arithmetic program
    , ProgramTest
        { progName = "Arithmetic Program"
        , program = createDevice [9, 14, 10, 15, 1, 11, 13, 0, 0, 0, 0, 0, 0, 0, 7, 3]
        -- LOAD R0,[14]; LOAD R1,[15]; ADD R0,R1; STORE R0,[13]; HALT
        , expectedSteps = 5
        , expectedFinalState = (createDevice [9, 14, 10, 15, 1, 11, 13, 0, 0, 0, 0, 0, 0, 10, 7, 3]) { r0 = 10, r1 = 3, pc = 8 }
        , expectedTotalOutput = 0
        , shouldTerminate = True
        }
        
    -- Conditional jump program
    , ProgramTest
        { progName = "Conditional Jump - Zero"
        , program = createDevice [14, 4, 3, 0, 0]  -- JZ [4], INC R0, HALT, HALT
        , expectedSteps = 2  -- JZ jumps to HALT
        , expectedFinalState = (createDevice [14, 4, 3, 0, 0]) { pc = 5 }
        , expectedTotalOutput = 0
        , shouldTerminate = True
        }
        
    , ProgramTest
        { progName = "Conditional Jump - Non-Zero"
        , program = createDevice [3, 14, 5, 3, 0, 0]  -- INC R0, JZ [5], INC R0, HALT, HALT
        , expectedSteps = 4  -- INC R0, JZ (no jump), INC R0, HALT
        , expectedFinalState = (createDevice [3, 14, 5, 3, 0, 0]) { r0 = 2, pc = 5 }
        , expectedTotalOutput = 0
        , shouldTerminate = True
        }
        
    -- Loop program (with safety limit)
    , ProgramTest
        { progName = "Simple Loop"
        , program = createDevice [3, 13, 0]  -- INC R0, JMP [0] - infinite loop
        , expectedSteps = 10001  -- Should hit timeout
        , expectedFinalState = (createDevice [3, 13, 0]) { r0 = 9, pc = 1 }  -- After 10000 iterations: (10000 * 2) & 0x0F = 4, but we need to account for actual execution
        , expectedTotalOutput = 0
        , shouldTerminate = False  -- Should timeout
        }
    ]

-- | Run all tests and return results
runAllTests :: IO [TestResult]
runAllTests = do
    putStrLn "Processor Instruction Set Test Suite"
    putStrLn "===================================="
    putStrLn ""
    
    -- Run instruction tests
    putStrLn "Testing Individual Instructions:"
    putStrLn "--------------------------------"
    let instrTests = createInstructionTests
        instrResults = map runInstructionTest instrTests
        instrPassed = length $ filter testPassed instrResults
        instrTotal = length instrResults
    
    mapM_ printTestResult instrResults
    putStrLn $ "Instruction Tests: " ++ show instrPassed ++ "/" ++ show instrTotal ++ " passed"
    putStrLn ""
    
    -- Run program tests
    putStrLn "Testing Complete Programs:"
    putStrLn "--------------------------"
    let progTests = createProgramTests
        progResults = map runProgramTest progTests
        progPassed = length $ filter testPassed progResults
        progTotal = length progResults
    
    mapM_ printTestResult progResults
    putStrLn $ "Program Tests: " ++ show progPassed ++ "/" ++ show progTotal ++ " passed"
    putStrLn ""
    
    -- Summary
    let allResults = instrResults ++ progResults
        totalPassed = length $ filter testPassed allResults
        totalTests = length allResults
    
    putStrLn "Summary:"
    putStrLn "--------"
    putStrLn $ "Total Tests: " ++ show totalPassed ++ "/" ++ show totalTests ++ " passed"
    
    if totalPassed == totalTests
    then putStrLn "🎉 ALL TESTS PASSED! 🎉"
    else putStrLn "❌ Some tests failed. See details above."
    
    return allResults

-- | Print a single test result
printTestResult :: TestResult -> IO ()
printTestResult TestResult{..} = do
    let status = if testPassed then "✅ PASS" else "❌ FAIL"
    putStrLn $ status ++ ": " ++ testName
    when (not testPassed) $ do
        putStrLn $ "  Expected: " ++ expectedResult
        putStrLn $ "  Actual:   " ++ actualResult
        case errorMessage of
            Just err -> putStrLn $ "  Error:    " ++ err
            Nothing -> return ()
        putStrLn ""
  where
    when True action = action
    when False _ = return ()