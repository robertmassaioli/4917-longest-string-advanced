module Commands.Generalize (runGeneralizeCommand) where

import qualified Data.Set as Set
import System.Exit (die)
import Commands.ProgramExecution (parseProgramBytes)
import TrackedProcessor
    ( createTrackedDevice
    , getAccessedLocations
    , getInstructionLocations
    , getOperandLocations
    , getOutput
    , getR0ContainsCombination
    , getR0WasConsumed
    , getR1WasConsumed
    , getSteps
    , isHalted
    , runTrackedProgramLoopCheck
    )
import WildcardPattern (analyzeProgram, optimizeProgram, prettyPrintOptimizedProgram)

-- | Execute a supplied program to halt or until its machine state repeats,
-- then print the memory usage observed and the corresponding wildcard pattern.
runGeneralizeCommand :: String -> IO ()
runGeneralizeCommand input = do
    suppliedBytes <- either die pure (parseProgramBytes input)
    let memoryImage = take 16 (suppliedBytes ++ repeat 0)
    initialDevice <- either (die . show) pure (createTrackedDevice memoryImage)
    let finalDevice = runTrackedProgramLoopCheck initialDevice
        analysis = analyzeProgram memoryImage finalDevice
        optimized = optimizeProgram analysis
        accessed = getAccessedLocations finalDevice
        unused = Set.fromList [0..15] `Set.difference` accessed

    putStrLn "Execution usage summary:"
    putStrLn $ "  Termination: " ++ if isHalted finalDevice then "halted" else "repeated machine state (loop)"
    putStrLn $ "  Steps: " ++ show (getSteps finalDevice)
    putStrLn $ "  Output characters: " ++ show (getOutput finalDevice)
    putStrLn $ "  Instruction locations: " ++ show (Set.toAscList (getInstructionLocations finalDevice))
    putStrLn $ "  Operand/data locations: " ++ show (Set.toAscList (getOperandLocations finalDevice))
    putStrLn $ "  Unused locations: " ++ show (Set.toAscList unused)
    putStrLn $ "  R0 consumed: " ++ show (getR0WasConsumed finalDevice)
    putStrLn $ "  R1 consumed: " ++ show (getR1WasConsumed finalDevice)
    putStrLn $ "  R0 contains R0/R1 combination: " ++ show (getR0ContainsCombination finalDevice)
    putStrLn ""
    putStrLn (prettyPrintOptimizedProgram optimized)

