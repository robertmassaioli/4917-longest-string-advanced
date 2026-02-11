module TrackedProcessor
    ( TrackedDevice(..)
    , Byte
    , createTrackedDevice
    , stepTrackedProgram
    , runTrackedProgram
    , runTrackedProgramLoopCheck
    , isHalted
    , getOutput
    , getPc
    , getR0
    , getR1
    , getMemory
    , getSteps
    , getAccessedLocations
    ) where

import Data.Vector.Unboxed (Vector, (!), (//))
import qualified Data.Vector.Unboxed as Vector
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Word (Word8)

type Byte = Word8

-- TrackedDevice - independent processor implementation with access tracking
data TrackedDevice = TrackedDevice
    { pc :: Byte                        -- Program Counter
    , r0 :: Byte                        -- Register R0
    , r1 :: Byte                        -- Register R1
    , memory :: Vector Byte             -- Full 16-byte memory
    , outputLength :: Int               -- Output character count
    , halted :: Bool                    -- Execution state
    , steps :: Int                      -- Step counter
    , accessedLocations :: Set Int      -- Which memory locations were read
    } deriving (Show, Eq)

-- Create TrackedDevice from program
createTrackedDevice :: [Byte] -> TrackedDevice
createTrackedDevice program = 
    let paddedProgram = take 16 (program ++ repeat 0)
        deviceMemory = Vector.fromList paddedProgram
    in TrackedDevice
        { pc = 0
        , r0 = 0
        , r1 = 0
        , memory = deviceMemory
        , outputLength = 0
        , halted = False
        , steps = 0
        , accessedLocations = Set.empty
        }

-- Accessor functions
isHalted :: TrackedDevice -> Bool
isHalted = halted

getOutput :: TrackedDevice -> Int
getOutput = outputLength

getPc :: TrackedDevice -> Byte
getPc = pc

getR0 :: TrackedDevice -> Byte
getR0 = r0

getR1 :: TrackedDevice -> Byte
getR1 = r1

getMemory :: TrackedDevice -> Vector Byte
getMemory = memory

getSteps :: TrackedDevice -> Int
getSteps = steps

getAccessedLocations :: TrackedDevice -> Set Int
getAccessedLocations = accessedLocations

-- Complete independent step function with integrated access tracking
stepTrackedProgram :: TrackedDevice -> TrackedDevice
stepTrackedProgram device
    | halted device = device
    | otherwise = 
        let currentPc = pc device
            instruction = memory device ! fromIntegral currentPc
            
            -- Track instruction fetch
            instructionAccess = Set.insert (fromIntegral currentPc) (accessedLocations device)
            
            -- Execute instruction and track additional accesses
            (newDevice, additionalAccesses) = executeInstructionWithTracking instruction device
            
            -- Combine all accessed locations
            allAccesses = Set.union instructionAccess additionalAccesses
            
        in newDevice { accessedLocations = allAccesses, steps = steps device + 1 }

-- Execute single instruction with memory access tracking
executeInstructionWithTracking :: Byte -> TrackedDevice -> (TrackedDevice, Set Int)
executeInstructionWithTracking instruction device =
    case instruction of
        -- HALT (0)
        0 -> (device { halted = True }, Set.empty)
        
        -- ADD (1): R0 = R0 + R1
        1 -> let newR0 = (r0 device + r1 device) `mod` 16
             in (device { r0 = newR0, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- SUB (2): R0 = R0 - R1  
        2 -> let newR0 = (r0 device - r1 device) `mod` 16
             in (device { r0 = newR0, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- INC R0 (3)
        3 -> (device { r0 = (r0 device + 1) `mod` 16, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- INC R1 (4)
        4 -> (device { r1 = (r1 device + 1) `mod` 16, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- DEC R0 (5)
        5 -> (device { r0 = (r0 device - 1) `mod` 16, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- DEC R1 (6)
        6 -> (device { r1 = (r1 device - 1) `mod` 16, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- NOP (7) - Ring Bell
        7 -> (device { pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- PRINT (8): Output value
        8 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                 value = memory device ! operandLoc
                 outputChars = if value < 10 then 1 else 2  -- 0-9: 1 char, 10-15: 2 chars
                 newDevice = device 
                     { pc = (pc device + 2) `mod` 16
                     , outputLength = outputLength device + outputChars
                     }
                 accesses = Set.singleton operandLoc
             in (newDevice, accesses)
        
        -- LOAD R0 (9): R0 = memory[operand]
        9 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                 address = memory device ! operandLoc
                 value = memory device ! fromIntegral address
                 newDevice = device { r0 = value, pc = (pc device + 2) `mod` 16 }
                 accesses = Set.fromList [operandLoc, fromIntegral address]
             in (newDevice, accesses)
        
        -- LOAD R1 (10): R1 = memory[operand]
        10 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  value = memory device ! fromIntegral address
                  newDevice = device { r1 = value, pc = (pc device + 2) `mod` 16 }
                  accesses = Set.fromList [operandLoc, fromIntegral address]
              in (newDevice, accesses)
        
        -- STORE R0 (11): memory[operand] = R0
        11 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newMemory = memory device // [(fromIntegral address, r0 device)]
                  newDevice = device { memory = newMemory, pc = (pc device + 2) `mod` 16 }
                  accesses = Set.singleton operandLoc  -- Only read operand, don't track writes
              in (newDevice, accesses)
        
        -- STORE R1 (12): memory[operand] = R1
        12 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newMemory = memory device // [(fromIntegral address, r1 device)]
                  newDevice = device { memory = newMemory, pc = (pc device + 2) `mod` 16 }
                  accesses = Set.singleton operandLoc  -- Only read operand, don't track writes
              in (newDevice, accesses)
        
        -- JMP (13): Unconditional jump
        13 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newDevice = device { pc = address `mod` 16 }
                  accesses = Set.singleton operandLoc
              in (newDevice, accesses)
        
        -- JZ (14): Jump if R0 == 0
        14 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newPc = if r0 device == 0 then address `mod` 16 else (pc device + 2) `mod` 16
                  newDevice = device { pc = newPc }
                  accesses = Set.singleton operandLoc
              in (newDevice, accesses)
        
        -- JNZ (15): Jump if R0 != 0
        15 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newPc = if r0 device /= 0 then address `mod` 16 else (pc device + 2) `mod` 16
                  newDevice = device { pc = newPc }
                  accesses = Set.singleton operandLoc
              in (newDevice, accesses)
        
        -- Invalid instruction - treat as NOP
        _ -> (device { pc = (pc device + 1) `mod` 16 }, Set.empty)

-- Run tracked program with step limit - independent implementation
runTrackedProgram :: TrackedDevice -> Int -> TrackedDevice
runTrackedProgram device 0 = device
runTrackedProgram device maxSteps
    | halted device = device
    | otherwise = runTrackedProgram (stepTrackedProgram device) (maxSteps - 1)

-- Loop detection version that tracks memory accesses - independent implementation
runTrackedProgramLoopCheck :: TrackedDevice -> TrackedDevice
runTrackedProgramLoopCheck = runTrackedProgramLoopCheck' Set.empty
  where
    runTrackedProgramLoopCheck' seenStates device
        | halted device = device
        | currentState `Set.member` seenStates = device  -- Loop detected
        | otherwise = runTrackedProgramLoopCheck' newSeenStates newDevice
      where
        currentState = (pc device, r0 device, r1 device)  -- Simple state representation
        newDevice = stepTrackedProgram device
        newSeenStates = Set.insert currentState seenStates