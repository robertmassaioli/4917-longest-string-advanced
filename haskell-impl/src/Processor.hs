{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE BangPatterns #-}

module Processor
    ( Device(..)
    , Byte
    , ProgramExecutionResult(..)
    , createDevice
    , initProgram
    , stepProgram
    , runProgram
    , runProgramLoopCheck
    , copyProgram
    , comparePrograms
    , programLength
    , runStep
    , isHalted
    , getOutput
    ) where

import Data.Word (Word8)
import Data.Bits ((.&.))
import qualified Data.Vector.Unboxed as V
import Data.Vector.Unboxed (Vector, (!), (//), fromList)

-- | Type alias for byte values (0-15 for this 4-bit machine)
type Byte = Word8

-- | Create a device with given memory contents
{-# INLINE createDevice #-}
createDevice :: [Byte] -> Device
createDevice memList = Device
    { memory = fromList $ take 16 (memList ++ repeat 0)
    , r0 = 0
    , r1 = 0
    , pc = 0
    , output = ""
    }

-- | The device structure representing the 4917 machine state
data Device = Device
    { memory :: !(Vector Byte)  -- 16 memory locations
    , r0     :: !Byte          -- Register 0
    , r1     :: !Byte          -- Register 1
    , pc     :: !Byte          -- Program Counter
    , output :: !String        -- Accumulated output
    } deriving (Show, Eq)

-- | Initialize a program to its starting state
{-# INLINE initProgram #-}
initProgram :: Device -> Device
initProgram device = device { r0 = 0, r1 = 0, pc = 0, output = "" }

-- | Perform a single step of program execution
-- Returns (newDevice, outputCount, programFinished)
{-# INLINE stepProgram #-}
stepProgram :: Device -> (Device, Int, Bool)
stepProgram device@Device{..} =
    let !instruction = memory ! fromIntegral pc
        !newPC = (pc + 1) .&. 0x0F
    in case instruction of
        -- Fast path for most common simple instructions
        3  -> (device { r0 = (r0 + 1) .&. 0x0F, pc = newPC }, 0, False)   -- INC R0
        7  -> (device { pc = newPC }, 0, False)  -- NOP
        0  -> (device { pc = newPC }, 0, True)  -- HALT
        4  -> (device { r1 = (r1 + 1) .&. 0x0F, pc = newPC }, 0, False)   -- INC R1
        5  -> (device { r0 = (r0 - 1) .&. 0x0F, pc = newPC }, 0, False)   -- DEC R0
        6  -> (device { r1 = (r1 - 1) .&. 0x0F, pc = newPC }, 0, False)   -- DEC R1
        1  -> (device { r0 = (r0 + r1) .&. 0x0F, pc = newPC }, 0, False)  -- ADD R0, R1
        2  -> (device { r0 = (r0 - r1) .&. 0x0F, pc = newPC }, 0, False)  -- SUB R0, R1
        -- Complex instructions need more computation
        8  -> let !nextPC = (newPC + 1) .&. 0x0F
                  !nextValue = memory ! fromIntegral newPC
                  !outputStr = show nextValue
                  !outputCount = length outputStr
                  !newOutput = output ++ outputStr
              in (device { pc = nextPC, output = newOutput }, outputCount, False)  -- OUTPUT

        9  -> let !nextPC = (newPC + 1) .&. 0x0F
                  !addr = memory ! fromIntegral newPC
                  !value = memory ! fromIntegral addr
              in (device { pc = nextPC, r0 = value }, 0, False)  -- LOAD R0, [addr]

        10 -> let !nextPC = (newPC + 1) .&. 0x0F
                  !addr = memory ! fromIntegral newPC
                  !value = memory ! fromIntegral addr
              in (device { pc = nextPC, r1 = value }, 0, False)  -- LOAD R1, [addr]

        11 -> let nextPC = (newPC + 1) .&. 0x0F
                  addr = memory ! fromIntegral newPC
                  newMemory = memory // [(fromIntegral addr, r0)]
              in (device { pc = nextPC, memory = newMemory }, 0, False)  -- STORE R0, [addr]

        12 -> let nextPC = (newPC + 1) .&. 0x0F
                  addr = memory ! fromIntegral newPC
                  newMemory = memory // [(fromIntegral addr, r1)]
              in (device { pc = nextPC, memory = newMemory }, 0, False)  -- STORE R1, [addr]

        13 -> let addr = memory ! fromIntegral newPC
              in (device { pc = addr }, 0, False)  -- JMP [addr]

        14 -> let addr = memory ! fromIntegral newPC
                  nextPC = if r0 == 0 then addr else (newPC + 1) .&. 0x0F
              in (device { pc = nextPC }, 0, False)  -- JZ [addr]

        15 -> let addr = memory ! fromIntegral newPC
                  nextPC = if r0 /= 0 then addr else (newPC + 1) .&. 0x0F
              in (device { pc = nextPC }, 0, False)  -- JNZ [addr]

        _  -> (device { pc = newPC }, 0, False)  -- Unknown instruction, treat as NOP

-- | Run a program with a timeout (in steps)
-- Returns the total output count, or 0 if timeout reached
{-# INLINE runProgram #-}
runProgram :: Device -> Int -> Int
runProgram device timeout = go (initProgram device) timeout 0
  where
    go _ 0 _ = 0  -- Timeout reached
    go dev t outputAcc
        | t >= 4 = -- Unroll 4 iterations at once
            let (!dev1, !out1, !fin1) = stepProgram dev
            in if fin1 then outputAcc + out1
               else let (!dev2, !out2, !fin2) = stepProgram dev1
                    in if fin2 then outputAcc + out1 + out2
                       else let (!dev3, !out3, !fin3) = stepProgram dev2
                            in if fin3 then outputAcc + out1 + out2 + out3
                               else let (!dev4, !out4, !fin4) = stepProgram dev3
                                        !newOutputAcc = outputAcc + out1 + out2 + out3 + out4
                                    in if fin4 then newOutputAcc
                                       else go dev4 (t - 4) newOutputAcc
        | otherwise = -- Handle remaining iterations normally
            let (!newDev, !output, !finished) = stepProgram dev
                !newOutputAcc = outputAcc + output
            in if finished
               then newOutputAcc
               else go newDev (t - 1) newOutputAcc

-- | Result of running a program with loop detection
data ProgramExecutionResult 
    = ProgramTerminated Int  -- ^ Program terminated normally with output count
    | InfiniteLoopDetected   -- ^ Infinite loop was detected
    deriving (Show, Eq)

-- | Run a program with loop detection using Floyd's cycle detection algorithm
-- Returns either the total output count if terminated, or InfiniteLoopDetected
runProgramLoopCheck :: Device -> ProgramExecutionResult
runProgramLoopCheck device = go slowDev fastDev 0
  where
    slowDev = initProgram device
    fastDev = initProgram device

    go slow fast outputAcc =
        let (newSlow, _, slowFinished) = stepProgram slow
            (fast1, output1, fast1Finished) = stepProgram fast
            (fast2, output2, fast2Finished) = if fast1Finished
                                              then (fast1, 0, True)
                                              else stepProgram fast1
            newOutputAcc = outputAcc + output1 + output2
        in if fast2Finished
           then ProgramTerminated newOutputAcc
           else if comparePrograms newSlow fast2
                then InfiniteLoopDetected  -- Loop detected
                else go newSlow fast2 newOutputAcc

-- | Copy a program (create a deep copy)
copyProgram :: Device -> Device
copyProgram = id  -- In Haskell, assignment creates a copy due to immutability

-- | Compare two programs for equality
comparePrograms :: Device -> Device -> Bool
comparePrograms = (==)  -- We derived Eq for Device

-- | Calculate the length of a program (last non-zero memory location + 1)
programLength :: Device -> Int
programLength Device{..} =
    case [i | i <- [15, 14 .. 0], memory ! i /= 0] of
        [] -> 0
        (i:_) -> i + 1

-- | Run a single step (for tracing support)
runStep :: Device -> Device
runStep device =
    let (newDevice, _, _) = stepProgram device
    in newDevice

-- | Check if device is halted
isHalted :: Device -> Bool
isHalted Device{..} =
    let instruction = memory ! fromIntegral pc
    in instruction == 0

-- | Get accumulated output
getOutput :: Device -> String
getOutput Device{..} = output