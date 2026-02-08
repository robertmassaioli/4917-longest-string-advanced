{-# LANGUAGE RecordWildCards #-}

module Processor
    ( Device(..)
    , Byte
    , createDevice
    , initProgram
    , stepProgram
    , runProgram
    , runProgramLoopCheck
    , copyProgram
    , comparePrograms
    , programLength
    ) where

import Data.Word (Word8)
import Data.Bits ((.&.))
import qualified Data.Vector as V
import Data.Vector (Vector, (!), (//), fromList)

-- | Type alias for byte values (0-15 for this 4-bit machine)
type Byte = Word8

-- | Create a device with given memory contents
createDevice :: [Byte] -> Device
createDevice memList = Device
    { memory = fromList $ take 16 (memList ++ repeat 0)
    , r0 = 0
    , r1 = 0
    , pc = 0
    }

-- | The device structure representing the 4917 machine state
data Device = Device
    { memory :: Vector Byte  -- 16 memory locations
    , r0     :: Byte         -- Register 0
    , r1     :: Byte         -- Register 1  
    , pc     :: Byte         -- Program Counter
    } deriving (Show, Eq)

-- | Initialize a program to its starting state
initProgram :: Device -> Device
initProgram device = device { r0 = 0, r1 = 0, pc = 0 }

-- | Perform a single step of program execution
-- Returns (newDevice, outputCount, programFinished)
stepProgram :: Device -> (Device, Int, Bool)
stepProgram device@Device{..} = 
    let instruction = memory ! fromIntegral pc
        newPC = (pc + 1) .&. 0x0F
        device' = device { pc = newPC }
    in case instruction of
        0  -> (device', 0, True)  -- HALT
        
        1  -> (device' { r0 = (r0 + r1) .&. 0x0F }, 0, False)  -- ADD R0, R1
        
        2  -> (device' { r0 = (r0 - r1) .&. 0x0F }, 0, False)  -- SUB R0, R1
        
        3  -> (device' { r0 = (r0 + 1) .&. 0x0F }, 0, False)   -- INC R0
        
        4  -> (device' { r1 = (r1 + 1) .&. 0x0F }, 0, False)   -- INC R1
        
        5  -> (device' { r0 = (r0 - 1) .&. 0x0F }, 0, False)   -- DEC R0
        
        6  -> (device' { r1 = (r1 - 1) .&. 0x0F }, 0, False)   -- DEC R1
        
        7  -> (device', 0, False)  -- NOP
        
        8  -> let nextPC = (newPC + 1) .&. 0x0F
                  nextValue = memory ! fromIntegral newPC
                  outputCount = if nextValue > 9 then 2 else 1
              in (device { pc = nextPC }, outputCount, False)  -- OUTPUT
        
        9  -> let nextPC = (newPC + 1) .&. 0x0F
                  addr = memory ! fromIntegral newPC
                  value = memory ! fromIntegral addr
              in (device { pc = nextPC, r0 = value }, 0, False)  -- LOAD R0, [addr]
        
        10 -> let nextPC = (newPC + 1) .&. 0x0F
                  addr = memory ! fromIntegral newPC
                  value = memory ! fromIntegral addr
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
        
        _  -> (device', 0, False)  -- Unknown instruction, treat as NOP

-- | Run a program with a timeout (in steps)
-- Returns the total output count, or 0 if timeout reached
runProgram :: Device -> Int -> Int
runProgram device timeout = go (initProgram device) timeout 0
  where
    go _ 0 _ = 0  -- Timeout reached
    go dev t outputAcc = 
        let (newDev, output, finished) = stepProgram dev
            newOutputAcc = outputAcc + output
        in if finished 
           then newOutputAcc
           else go newDev (t - 1) newOutputAcc

-- | Run a program with loop detection using Floyd's cycle detection algorithm
-- Returns the total output count, or 0 if infinite loop detected
runProgramLoopCheck :: Device -> Int
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
           then newOutputAcc
           else if comparePrograms newSlow fast2
                then 0  -- Loop detected
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