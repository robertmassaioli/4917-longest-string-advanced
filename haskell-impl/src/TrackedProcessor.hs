module TrackedProcessor
    ( TrackedDevice(..)
    , ValidationError(..)
    , ErrorType(..)
    , Byte
    -- Usage tracking data types
    , MemoryUsage(..)
    , UsageType(..)
    , UsageContext(..)
    , AccessType(..)
    -- Main functions
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
    , getInstructionLocations
    , getOperandLocations
    , getInstructionOnlyLocations
    , getOperandOnlyLocations
    , getMixedUsageLocations
    , getR0WasConsumed
    , getR1WasConsumed
    , getR0ContainsCombination
    , getDetailedUsage
    , classifyRegisterConsumption
    ) where

import Data.Vector.Unboxed (Vector, (!), (//))
import qualified Data.Vector.Unboxed as Vector
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Word (Word8)
import qualified Data.Map as Map

type Byte = Word8

-- Forward declarations for usage tracking data structures
-- (Detailed definitions are in WildcardPattern.hs to avoid circular imports)

-- | Detailed information about how a memory position was used during execution
data MemoryUsage = MemoryUsage
    { position :: Int
    , usageTypes :: [UsageType]
    , contextInfo :: [UsageContext]
    } deriving (Show, Eq)

-- | Different ways a memory position can be used
data UsageType 
    = UsedAsInstruction String      -- instruction name
    | UsedAsOperand String Int      -- instruction name + operand index
    | NeverAccessed
    deriving (Show, Eq)

-- | Context information for when a memory position was accessed
data UsageContext = UsageContext
    { accessPC :: Int           -- Program counter when accessed
    , accessStep :: Int         -- Execution step number
    , accessType :: AccessType
    } deriving (Show, Eq)

-- | Type of memory access
data AccessType 
    = InstructionFetch
    | OperandRead Int           -- operand index (0 for single operand)
    deriving (Show, Eq)

-- Validation error types for program validation
data ValidationError = ValidationError
    { errorType :: ErrorType
    , errorMessage :: String
    , errorPosition :: Maybe Int  -- Position in program where error occurred
    } deriving (Show, Eq)

data ErrorType 
    = InvalidInstructionValue
    | ProgramTooLong
    | EmptyProgram
    deriving (Show, Eq)

-- TrackedDevice - independent processor implementation with access tracking
data TrackedDevice = TrackedDevice
    { pc :: Byte                        -- Program Counter
    , r0 :: Byte                        -- Register R0
    , r1 :: Byte                        -- Register R1
    , memory :: Vector Byte             -- Full 16-byte memory
    , outputLength :: Int               -- Output character count
    , halted :: Bool                    -- Execution state
    , steps :: Int                      -- Step counter
    , r0WasConsumed :: Bool             -- True if R0 was ever consumed
    , r1WasConsumed :: Bool             -- True if R1 was ever consumed
    , r0ContainsCombination :: Bool     -- True if R0 contains result of ADD/SUB using both registers
    , instructionLocations :: Set Int   -- Positions accessed as instructions (PC reads)
    , operandLocations :: Set Int       -- Positions accessed as operands (instruction parameter reads)
    , detailedUsage :: Map.Map Int MemoryUsage  -- NEW: detailed usage tracking
    } deriving (Show, Eq)

-- Create TrackedDevice from program with validation
createTrackedDevice :: [Byte] -> Either ValidationError TrackedDevice
createTrackedDevice program = do
    validatedProgram <- validateProgram program
    let paddedProgram = take 16 (validatedProgram ++ repeat 0)
        deviceMemory = Vector.fromList paddedProgram
    return TrackedDevice
        { pc = 0
        , r0 = 0
        , r1 = 0
        , memory = deviceMemory
        , outputLength = 0
        , halted = False
        , steps = 0
        , r0WasConsumed = False
        , r1WasConsumed = False
        , r0ContainsCombination = False
        , instructionLocations = Set.empty
        , operandLocations = Set.empty
        , detailedUsage = Map.empty
        }

-- Validate program for 4-bit processor constraints
validateProgram :: [Byte] -> Either ValidationError [Byte]
validateProgram [] = Left $ ValidationError EmptyProgram "Program cannot be empty" Nothing
validateProgram program 
    | length program > 16 = Left $ ValidationError ProgramTooLong 
        ("Program length " ++ show (length program) ++ " exceeds maximum of 16 instructions") Nothing
    | otherwise = validateInstructions program 0

-- Validate each instruction in the program
validateInstructions :: [Byte] -> Int -> Either ValidationError [Byte]
validateInstructions [] _ = Right []
validateInstructions (instr:rest) pos
    | instr > 15 = Left $ ValidationError InvalidInstructionValue 
        ("Invalid instruction value " ++ show instr ++ " at position " ++ show pos ++ ". Must be 0-15.") (Just pos)
    | instr >= 8 = -- Two-byte instruction, process operand
        case rest of
            [] -> -- Missing operand, pad with 0
                return [instr, 0]
            (operand:remaining) -> do
                validatedRest <- validateInstructions remaining (pos + 2)
                return (instr : operand : validatedRest)
    | otherwise = do -- Single-byte instruction
        validatedRest <- validateInstructions rest (pos + 1)
        return (instr : validatedRest)

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

-- Updated: Now derived from instruction and operand locations
getAccessedLocations :: TrackedDevice -> Set Int
getAccessedLocations device = 
    instructionLocations device `Set.union` operandLocations device

-- New accessor functions for enhanced tracking
getInstructionLocations :: TrackedDevice -> Set Int
getInstructionLocations = instructionLocations

getOperandLocations :: TrackedDevice -> Set Int  
getOperandLocations = operandLocations

-- Derived analysis functions
getInstructionOnlyLocations :: TrackedDevice -> Set Int
getInstructionOnlyLocations device = 
    instructionLocations device `Set.difference` operandLocations device

getOperandOnlyLocations :: TrackedDevice -> Set Int
getOperandOnlyLocations device = 
    operandLocations device `Set.difference` instructionLocations device

getMixedUsageLocations :: TrackedDevice -> Set Int
getMixedUsageLocations device = 
    instructionLocations device `Set.intersection` operandLocations device

getR0WasConsumed :: TrackedDevice -> Bool
getR0WasConsumed = r0WasConsumed

getR1WasConsumed :: TrackedDevice -> Bool
getR1WasConsumed = r1WasConsumed

getR0ContainsCombination :: TrackedDevice -> Bool
getR0ContainsCombination = r0ContainsCombination

-- New accessor for detailed usage tracking
getDetailedUsage :: TrackedDevice -> Map.Map Int MemoryUsage
getDetailedUsage = detailedUsage

-- | Determine which registers an instruction consumes, accounting for combination tracking
classifyRegisterConsumption :: Byte -> TrackedDevice -> (Bool, Bool)  -- (consumesR0, consumesR1)
classifyRegisterConsumption instruction device = case instruction of
    11 -> (True, r0ContainsCombination device)  -- STORE R0: uses R0, and R1 if R0 contains combination
    12 -> (False, True)                         -- STORE R1: uses R1 directly
    14 -> (True, r0ContainsCombination device)  -- JZ: uses R0, and R1 if R0 contains combination  
    15 -> (True, r0ContainsCombination device)  -- JNZ: uses R0, and R1 if R0 contains combination
    _  -> (False, False)                        -- All other instructions don't consume register values

-- | Helper functions for detailed usage tracking

-- | Get instruction name for a given opcode
getInstructionName :: Byte -> String
getInstructionName instruction = case instruction of
    0 -> "HALT"
    1 -> "ADD"
    2 -> "SUB"
    3 -> "INC R0"
    4 -> "INC R1"
    5 -> "DEC R0"
    6 -> "DEC R1"
    7 -> "NOP"
    8 -> "PRINT"
    9 -> "LOAD R0"
    10 -> "LOAD R1"
    11 -> "STORE R0"
    12 -> "STORE R1"
    13 -> "JMP"
    14 -> "JZ"
    15 -> "JNZ"
    _ -> "UNKNOWN"

-- | Record instruction usage for a memory position
recordInstructionUsage :: Int -> String -> Int -> Int -> TrackedDevice -> TrackedDevice
recordInstructionUsage pos instrName pc step device =
    let usage = case Map.lookup pos (detailedUsage device) of
            Nothing -> MemoryUsage pos [UsedAsInstruction instrName] 
                          [UsageContext pc step InstructionFetch]
            Just existing -> existing 
                { usageTypes = UsedAsInstruction instrName : usageTypes existing
                , contextInfo = UsageContext pc step InstructionFetch : contextInfo existing
                }
    in device { detailedUsage = Map.insert pos usage (detailedUsage device) }

-- | Record operand usage for a memory position
recordOperandUsage :: Int -> String -> Int -> Int -> Int -> TrackedDevice -> TrackedDevice
recordOperandUsage pos instrName operandIndex pc step device =
    let usage = case Map.lookup pos (detailedUsage device) of
            Nothing -> MemoryUsage pos [UsedAsOperand instrName operandIndex]
                          [UsageContext pc step (OperandRead operandIndex)]
            Just existing -> existing
                { usageTypes = UsedAsOperand instrName operandIndex : usageTypes existing
                , contextInfo = UsageContext pc step (OperandRead operandIndex) : contextInfo existing
                }
    in device { detailedUsage = Map.insert pos usage (detailedUsage device) }

-- Complete independent step function with integrated access tracking
stepTrackedProgram :: TrackedDevice -> TrackedDevice
stepTrackedProgram device
    | halted device = device
    | otherwise = 
        let currentPc = fromIntegral (pc device)
            instruction = memory device ! currentPc
            instrName = getInstructionName instruction
            currentStep = steps device
            
            -- Track that current PC was accessed as an instruction (both old and new tracking)
            deviceWithInstrTracking = device 
                { instructionLocations = Set.insert currentPc (instructionLocations device) }
            
            -- Record detailed instruction usage
            deviceWithDetailedInstr = recordInstructionUsage currentPc instrName currentPc currentStep deviceWithInstrTracking
            
            -- Execute instruction and track operand accesses
            (newDevice, operandAccesses) = executeInstructionWithTracking instruction deviceWithDetailedInstr
            
            -- Update operand locations with any new accesses (old tracking)
            deviceWithOperandTracking = newDevice { operandLocations = Set.union (operandLocations newDevice) operandAccesses }
            
            -- Record detailed operand usage for each operand access
            finalDevice = Set.foldl (recordDetailedOperandUsage instrName currentPc currentStep) deviceWithOperandTracking operandAccesses
            
        in finalDevice { steps = steps device + 1 }

-- | Helper to record detailed operand usage
recordDetailedOperandUsage :: String -> Int -> Int -> TrackedDevice -> Int -> TrackedDevice
recordDetailedOperandUsage instrName pc step device operandPos =
    recordOperandUsage operandPos instrName 0 pc step device

-- Execute single instruction with memory access tracking
executeInstructionWithTracking :: Byte -> TrackedDevice -> (TrackedDevice, Set Int)
executeInstructionWithTracking instruction device =
    case instruction of
        -- HALT (0)
        0 -> (device { halted = True }, Set.empty)
        
        -- ADD (1): R0 = R0 + R1
        1 -> let newR0 = (r0 device + r1 device) `mod` 16
                 -- R0 now contains a combination of both registers
                 combinationDevice = device { r0ContainsCombination = True }
             in (combinationDevice { r0 = newR0, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
        -- SUB (2): R0 = R0 - R1  
        2 -> let newR0 = (r0 device - r1 device) `mod` 16
                 -- R0 now contains a combination of both registers
                 combinationDevice = device { r0ContainsCombination = True }
             in (combinationDevice { r0 = newR0, pc = (pc device + 1) `mod` 16 }, Set.empty)
        
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
                 operandAccesses = Set.singleton operandLoc  -- Only the operand position
             in (newDevice, operandAccesses)
        
        -- LOAD R0 (9): R0 = memory[operand]
        9 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                 address = memory device ! operandLoc
                 dataLoc = fromIntegral address
                 value = memory device ! dataLoc
                 newDevice = device { r0 = value, pc = (pc device + 2) `mod` 16 }
                 -- Return both operand and data accesses for backward compatibility
                 operandAccesses = Set.fromList [operandLoc, dataLoc]
             in (newDevice, operandAccesses)
        
        -- LOAD R1 (10): R1 = memory[operand]
        10 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  dataLoc = fromIntegral address
                  value = memory device ! dataLoc
                  newDevice = device { r1 = value, pc = (pc device + 2) `mod` 16 }
                  -- Return both operand and data accesses for backward compatibility
                  operandAccesses = Set.fromList [operandLoc, dataLoc]
              in (newDevice, operandAccesses)
        
        -- STORE R0 (11): memory[operand] = R0
        11 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newMemory = memory device // [(fromIntegral address, r0 device)]
                  -- Classify consumption based on combination tracking
                  (consumesR0, consumesR1) = classifyRegisterConsumption 11 device
                  consumedDevice = device { r0WasConsumed = r0WasConsumed device || consumesR0
                                          , r1WasConsumed = r1WasConsumed device || consumesR1 }
                  newDevice = consumedDevice { memory = newMemory, pc = (pc device + 2) `mod` 16 }
                  operandAccesses = Set.singleton operandLoc  -- Only the operand access
              in (newDevice, operandAccesses)
        
        -- STORE R1 (12): memory[operand] = R1
        12 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newMemory = memory device // [(fromIntegral address, r1 device)]
                  -- R1 is always consumed directly
                  consumedDevice = device { r1WasConsumed = True }
                  newDevice = consumedDevice { memory = newMemory, pc = (pc device + 2) `mod` 16 }
                  operandAccesses = Set.singleton operandLoc  -- Only the operand access
              in (newDevice, operandAccesses)
        
        -- JMP (13): Unconditional jump
        13 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newDevice = device { pc = address `mod` 16 }
                  operandAccesses = Set.singleton operandLoc
              in (newDevice, operandAccesses)
        
        -- JZ (14): Jump if R0 == 0
        14 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newPc = if r0 device == 0 then address `mod` 16 else (pc device + 2) `mod` 16
                  -- Classify consumption based on combination tracking
                  (consumesR0, consumesR1) = classifyRegisterConsumption 14 device
                  consumedDevice = device { r0WasConsumed = r0WasConsumed device || consumesR0
                                          , r1WasConsumed = r1WasConsumed device || consumesR1 }
                  newDevice = consumedDevice { pc = newPc }
                  operandAccesses = Set.singleton operandLoc
              in (newDevice, operandAccesses)
        
        -- JNZ (15): Jump if R0 != 0
        15 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                  address = memory device ! operandLoc
                  newPc = if r0 device /= 0 then address `mod` 16 else (pc device + 2) `mod` 16
                  -- Classify consumption based on combination tracking
                  (consumesR0, consumesR1) = classifyRegisterConsumption 15 device
                  consumedDevice = device { r0WasConsumed = r0WasConsumed device || consumesR0
                                          , r1WasConsumed = r1WasConsumed device || consumesR1 }
                  newDevice = consumedDevice { pc = newPc }
                  operandAccesses = Set.singleton operandLoc
              in (newDevice, operandAccesses)
        
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