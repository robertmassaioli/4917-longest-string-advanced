{-# LANGUAGE RecordWildCards #-}

module SolveTask
    ( solveTask
    , printProgram
    ) where

import Data.Word (Word32)
import qualified Data.Vector.Unboxed as V
import Data.Vector.Unboxed ((!), (//))
import Data.Bits ((.&.))
import Processor (Device(..), Byte, ProgramExecutionResult(..), runProgramLoopCheck, programLength)
import PackProcessor (unpackHalfDevice, packDevice)
import ClientResults (ClientResults, newClientResults, addResult)

-- | Maximum level for the nested loop counter
maxLevel :: Int
maxLevel = 16

-- | Solve a task by generating and testing program variations
-- This mirrors the C++ solveTask function logic
solveTask :: Word32 -> ClientResults
solveTask task = 
    let -- Setup the initial program from the task
        initialProgram = unpackHalfDevice task
        clientResults = newClientResults task
    in if memory initialProgram ! 0 /= 0
       then solveLoop initialProgram clientResults
       else clientResults

-- | Main solving loop that generates program variations
solveLoop :: Device -> ClientResults -> ClientResults
solveLoop currentProgram clientResults = go currentProgram clientResults
  where
    go program results = 
        let (newProgram, shouldContinue) = incrementProgram program 8
        in if not shouldContinue
           then results
           else let result = runProgramLoopCheck newProgram
                    charactersPrinted = case result of
                        ProgramTerminated count -> count
                        InfiniteLoopDetected -> 0  -- Treat infinite loops as producing no useful output
                    packedProgram = packDevice newProgram
                    updatedResults = addResult results newProgram charactersPrinted packedProgram
                in go newProgram updatedResults

-- | Increment the program counter starting from a given position
-- This implements the nested loop logic from the C++ code
incrementProgram :: Device -> Int -> (Device, Bool)
incrementProgram program startCounter = go program startCounter
  where
    go currentProgram counter
        | counter >= maxLevel = (currentProgram, False)  -- Reached max level, stop
        | otherwise = 
            let currentValue = memory currentProgram ! counter
                newValue = (currentValue + 1) .&. 0x0F
                updatedProgram = currentProgram { memory = memory currentProgram // [(counter, newValue)] }
            in if newValue == 0
               then go updatedProgram (counter + 1)  -- Carry over, continue to next position
               else 
                   -- Print debug info if we're at high counters (like C++ code)
                   let shouldPrint = counter > 14
                       result = (updatedProgram, True)
                   in if shouldPrint
                      then result  -- For now, just ignore tracing
                      else result

-- | Print a program's memory contents (for debugging)
printProgram :: Device -> String
printProgram Device{..} = 
    unwords [show (fromIntegral (memory ! i) :: Int) | i <- [0..15]]