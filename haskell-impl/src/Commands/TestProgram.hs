module Commands.TestProgram (runTestProgramCommand) where

import Processor
import TrackedProcessor (runTrackedProgramLoopCheck, createTrackedDevice, getOutput, isHalted)
import WildcardPattern (analyzeProgram, optimizeProgram, prettyPrintOptimizedProgram)
import Data.List (intercalate)

-- | Test a specific program given as a list of bytes
runTestProgramCommand :: [Int] -> IO ()
runTestProgramCommand program = do
    let bytes = map fromIntegral program
    let device = createDevice bytes
    let result = runProgramLoopCheck device
    
    putStrLn $ "Testing program: [" ++ intercalate ", " (map show program) ++ "]"
    putStrLn $ "Program length: " ++ show (programLength device)
    
    case result of
        ProgramTerminated outputCount -> do
            putStrLn $ "Result: ✓ Program terminated"
            putStrLn $ "Output length: " ++ show outputCount ++ " characters"
            
            -- Generate and display optimized program representation
            case createTrackedDevice bytes of
                Left err -> putStrLn $ "Warning: Could not create tracked device: " ++ show err
                Right trackedDevice -> do
                    let finalDevice = runTrackedProgramLoopCheck trackedDevice
                        analysis = analyzeProgram bytes finalDevice
                        optProg = optimizeProgram analysis
                    putStrLn ""
                    putStrLn "Optimized representation:"
                    putStrLn $ prettyPrintOptimizedProgram optProg
                    
        InfiniteLoopDetected -> do
            putStrLn $ "Result: ✗ Infinite loop detected"
            putStrLn $ "Output length: N/A (does not halt)"
