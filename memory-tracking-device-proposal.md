# TrackedProcessor Module Proposal
## Independent Implementation with Memory Access Tracking

### Project Overview
Create a new `TrackedProcessor` module that provides a completely independent implementation of the 4917 processor with built-in memory access tracking functionality. This will be a forked implementation that doesn't depend on the original Processor module.

---

## Problem Statement

### Current Limitation
When analyzing programs on the 4917 processor, we have no visibility into which memory locations actually matter for program execution.

**Example:**
```haskell
-- These programs behave identically but we can't detect it:
[8, 15, 0]                    -- PRINT 15, HALT
[8, 15, 0, 42, 99, 123, ...]  -- PRINT 15, HALT + unused data

-- Both only read memory locations 0, 1, 2 during execution
```

---

## Solution: Independent TrackedProcessor Module

### Core Enhancement
Create a completely independent processor implementation that includes memory access tracking as a core feature, without any dependency on the original Processor module.

---

## Independent TrackedProcessor Module Architecture

### Complete Independent Implementation
**File**: `src/TrackedProcessor.hs`
```haskell
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
    , isHalted :: Bool                  -- Execution state
    , steps :: Int                      -- Step counter
    , accessedLocations :: Set Int      -- Which memory locations were read
    } deriving (Show, Eq)

-- Create TrackedDevice from program
createTrackedDevice :: [Byte] -> TrackedDevice
createTrackedDevice program = 
    let paddedProgram = take 16 (program ++ repeat 0)
        memory = Vector.fromList paddedProgram
    in TrackedDevice
        { pc = 0
        , r0 = 0
        , r1 = 0
        , memory = memory
        , outputLength = 0
        , isHalted = False
        , steps = 0
        , accessedLocations = Set.empty
        }

-- Accessor functions
isHalted :: TrackedDevice -> Bool
isHalted = TrackedProcessor.isHalted

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
```

## Independent TrackedProcessor Functions

### stepTrackedProgram Function
```haskell
-- Complete independent step function with integrated access tracking
stepTrackedProgram :: TrackedDevice -> TrackedDevice
stepTrackedProgram device
    | TrackedProcessor.isHalted device = device
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
        0 -> (device { TrackedProcessor.isHalted = True }, Set.empty)
        
        -- ADD (1): R0 = R0 + R1
        1 -> let newR0 = (r0 device + r1 device) `mod` 16
             in (device { r0 = newR0, pc = pc device + 1 }, Set.empty)
        
        -- SUB (2): R0 = R0 - R1  
        2 -> let newR0 = (r0 device - r1 device) `mod` 16
             in (device { r0 = newR0, pc = pc device + 1 }, Set.empty)
        
        -- INC R0 (3)
        3 -> (device { r0 = (r0 device + 1) `mod` 16, pc = pc device + 1 }, Set.empty)
        
        -- INC R1 (4)
        4 -> (device { r1 = (r1 device + 1) `mod` 16, pc = pc device + 1 }, Set.empty)
        
        -- DEC R0 (5)
        5 -> (device { r0 = (r0 device - 1) `mod` 16, pc = pc device + 1 }, Set.empty)
        
        -- DEC R1 (6)
        6 -> (device { r1 = (r1 device - 1) `mod` 16, pc = pc device + 1 }, Set.empty)
        
        -- NOP (7) - Ring Bell
        7 -> (device { pc = pc device + 1 }, Set.empty)
        
        -- PRINT (8): Output value
        8 -> let operandLoc = fromIntegral (pc device + 1)
                 value = memory device ! operandLoc
                 outputChars = if value < 10 then 1 else 2  -- 0-9: 1 char, 10-15: 2 chars
                 newDevice = device 
                     { pc = pc device + 2
                     , outputLength = outputLength device + outputChars
                     }
                 accesses = Set.singleton operandLoc
             in (newDevice, accesses)
        
        -- LOAD R0 (9): R0 = memory[operand]
        9 -> let operandLoc = fromIntegral (pc device + 1)
                 address = memory device ! operandLoc
                 value = memory device ! fromIntegral address
                 newDevice = device { r0 = value, pc = pc device + 2 }
                 accesses = Set.fromList [operandLoc, fromIntegral address]
             in (newDevice, accesses)
        
        -- LOAD R1 (10): R1 = memory[operand]
        10 -> let operandLoc = fromIntegral (pc device + 1)
                  address = memory device ! operandLoc
                  value = memory device ! fromIntegral address
                  newDevice = device { r1 = value, pc = pc device + 2 }
                  accesses = Set.fromList [operandLoc, fromIntegral address]
              in (newDevice, accesses)
        
        -- STORE R0 (11): memory[operand] = R0
        11 -> let operandLoc = fromIntegral (pc device + 1)
                  address = memory device ! operandLoc
                  newMemory = memory device // [(fromIntegral address, r0 device)]
                  newDevice = device { memory = newMemory, pc = pc device + 2 }
                  accesses = Set.singleton operandLoc  -- Only read operand, don't track writes
              in (newDevice, accesses)
        
        -- STORE R1 (12): memory[operand] = R1
        12 -> let operandLoc = fromIntegral (pc device + 1)
                  address = memory device ! operandLoc
                  newMemory = memory device // [(fromIntegral address, r1 device)]
                  newDevice = device { memory = newMemory, pc = pc device + 2 }
                  accesses = Set.singleton operandLoc  -- Only read operand, don't track writes
              in (newDevice, accesses)
        
        -- JMP (13): Unconditional jump
        13 -> let operandLoc = fromIntegral (pc device + 1)
                  address = memory device ! operandLoc
                  newDevice = device { pc = address }
                  accesses = Set.singleton operandLoc
              in (newDevice, accesses)
        
        -- JZ (14): Jump if R0 == 0
        14 -> let operandLoc = fromIntegral (pc device + 1)
                  address = memory device ! operandLoc
                  newPc = if r0 device == 0 then address else pc device + 2
                  newDevice = device { pc = newPc }
                  accesses = Set.singleton operandLoc
              in (newDevice, accesses)
        
        -- JNZ (15): Jump if R0 != 0
        15 -> let operandLoc = fromIntegral (pc device + 1)
                  address = memory device ! operandLoc
                  newPc = if r0 device /= 0 then address else pc device + 2
                  newDevice = device { pc = newPc }
                  accesses = Set.singleton operandLoc
              in (newDevice, accesses)
        
        -- Invalid instruction - treat as NOP
        _ -> (device { pc = pc device + 1 }, Set.empty)
```

### runTrackedProgram Function
```haskell
-- Run tracked program with step limit - independent implementation
runTrackedProgram :: TrackedDevice -> Int -> TrackedDevice
runTrackedProgram device 0 = device
runTrackedProgram device maxSteps
    | TrackedProcessor.isHalted device = device
    | otherwise = runTrackedProgram (stepTrackedProgram device) (maxSteps - 1)
```

### runTrackedProgramLoopCheck Function  
```haskell
-- Loop detection version that tracks memory accesses - independent implementation
runTrackedProgramLoopCheck :: TrackedDevice -> TrackedDevice
runTrackedProgramLoopCheck = runTrackedProgramLoopCheck' Set.empty
  where
    runTrackedProgramLoopCheck' seenStates device
        | TrackedProcessor.isHalted device = device
        | currentState `Set.member` seenStates = device  -- Loop detected
        | otherwise = runTrackedProgramLoopCheck' newSeenStates newDevice
      where
        currentState = (pc device, r0 device, r1 device)  -- Simple state representation
        newDevice = stepTrackedProgram device
        newSeenStates = Set.insert currentState seenStates
```

## TrackedProcessor Test Cases

### Test File Structure  
**File**: `test/TrackedProcessorSpec.hs`
```haskell
module TrackedProcessorSpec (spec) where

import Test.Hspec
import TrackedProcessor
import Data.Set (Set)
import qualified Data.Set as Set

spec :: Spec
spec = describe "TrackedProcessor" $ do
  context "Basic Functionality" $ do
    it "creates TrackedDevice from program" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT
          tracked = createTrackedDevice program
      getAccessedLocations tracked `shouldBe` Set.empty
      isHalted tracked `shouldBe` False

    it "preserves original Device functionality" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT
          tracked = createTrackedDevice program
          finalTracked = runTrackedProgram tracked 10
      isHalted finalTracked `shouldBe` True
      getOutput finalTracked `shouldBe` 2

  context "Memory Access Tracking" $ do
    it "tracks instruction fetches for single-byte instructions" $ do
      let program = [3, 0]  -- INC R0, HALT
          tracked = createTrackedDevice program
          stepped = stepTrackedProgram tracked
      getAccessedLocations stepped `shouldBe` Set.fromList [0]

    it "tracks instruction and operand for two-byte instructions" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT  
          tracked = createTrackedDevice program
          stepped = stepTrackedProgram tracked
      getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

    it "tracks LOAD R0 instruction with data access" $ do
      let program = [9, 3, 0, 42]  -- LOAD R0 from address 3, HALT, data
          tracked = createTrackedDevice program
          stepped = stepTrackedProgram tracked
      getAccessedLocations stepped `shouldBe` Set.fromList [0, 1, 3]

    it "tracks LOAD R1 instruction with data access" $ do
      let program = [10, 4, 0, 0, 99]  -- LOAD R1 from address 4, HALT, padding, data
          tracked = createTrackedDevice program  
          stepped = stepTrackedProgram tracked
      getAccessedLocations stepped `shouldBe` Set.fromList [0, 1, 4]

    it "tracks multiple steps accumulating access locations" $ do
      let program = [8, 15, 8, 10, 0]  -- PRINT 15, PRINT 10, HALT
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked
          step2 = stepTrackedProgram step1
          step3 = stepTrackedProgram step2
      getAccessedLocations step3 `shouldBe` Set.fromList [0, 1, 2, 3, 4]

  context "Program Execution" $ do
    it "runTrackedProgram preserves access tracking" $ do
      let program = [8, 15, 8, 10, 0]  -- PRINT 15, PRINT 10, HALT
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 10
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2, 3, 4]
      isHalted final `shouldBe` True

    it "runTrackedProgramLoopCheck detects loops while tracking" $ do
      let program = [3, 13, 0]  -- INC R0, JMP 0 (infinite loop)
          tracked = createTrackedDevice program
          final = runTrackedProgramLoopCheck tracked
      -- Should access locations 0 (INC), 1 (JMP operand), 2 (JMP instruction) multiple times
      Set.isSubsetOf (Set.fromList [0, 1, 2]) (getAccessedLocations final) `shouldBe` True
      -- Loop should be detected (not halted, but stopped by loop detection)

  context "Memory Access Patterns" $ do  
    it "identifies minimal memory footprint" $ do
      let program = [8, 15, 0, 99, 99, 99]  -- PRINT 15, HALT + unused data
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 10
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2]
      -- Should not access unused locations 3, 4, 5

    it "tracks data reads separately from instructions" $ do
      let program = [9, 5, 0, 0, 0, 123]  -- LOAD R0 from address 5, HALT, padding, data
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked  -- Execute LOAD
          step2 = stepTrackedProgram step1    -- Execute HALT
      getAccessedLocations step2 `shouldBe` Set.fromList [0, 1, 2, 5]

    it "handles STORE instructions (no data read)" $ do  
      let program = [11, 5, 0]  -- STORE R0 to address 5, HALT
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked
          step2 = stepTrackedProgram step1
      getAccessedLocations step2 `shouldBe` Set.fromList [0, 1, 2]
      -- Should not include address 5 since STORE writes, doesn't read

  context "Complex Programs" $ do
    it "tracks conditional jump programs" $ do
      let program = [14, 4, 3, 0, 5, 0]  -- JZ 4, INC R0, HALT, DEC R0, HALT
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 10
      -- Exact access pattern depends on R0 initial value and execution path
      Set.size (getAccessedLocations final) `shouldSatisfy` (>= 3)

    it "tracks loop with memory access" $ do
      let program = [9, 8, 3, 13, 0, 0, 0, 0, 42]  -- LOAD R0 from 8, INC R0, JMP 0, padding, data
          tracked = createTrackedDevice program  
          final = runTrackedProgramLoopCheck tracked
      -- Should access: 0,1,8 (LOAD), 2 (INC), 3,4 (JMP)
      Set.isSubsetOf (Set.fromList [0, 1, 2, 3, 8]) (getAccessedLocations final) `shouldBe` True
```

## Implementation Plan

### TrackedProcessor Module Implementation (2-3 hours)
- [ ] Create `src/TrackedProcessor.hs` module
- [ ] Implement `TrackedDevice` data type wrapping `Device`
- [ ] Implement `stepTrackedProgram` with memory access tracking  
- [ ] Implement `runTrackedProgram` and `runTrackedProgramLoopCheck` functions
- [ ] Add helper functions for memory access detection

### Test Suite Implementation (1-2 hours)
- [ ] Create `test/TrackedProcessorSpec.hs` test file
- [ ] Implement basic functionality tests
- [ ] Implement memory access tracking tests
- [ ] Implement program execution tests  
- [ ] Implement complex program tests
- [ ] Add to main test suite

### Integration (30 minutes)
- [ ] Update cabal file to include new module and test
- [ ] Verify all tests pass
- [ ] Document module API

## Expected Benefits

### Independent Implementation Benefits
- **Self-contained**: No dependencies on original Processor module
- **Optimized**: Can optimize specifically for tracking use cases
- **Simplified**: Single module with integrated tracking functionality
- **Extensible**: Easy to add more tracking features without compatibility concerns

### Analysis Capabilities
- **Memory Footprint**: See exactly which locations each program uses
- **Access Patterns**: Understand program behavior through memory usage
- **Program Equivalence Foundation**: Enable future equivalence detection
- **Debugging**: Visualize program memory access for analysis

## Summary

This proposal creates a completely independent `TrackedProcessor` module that implements the full 4917 processor functionality with integrated memory access tracking. The design provides a clean, self-contained implementation without any dependencies on the original Processor module.

**Key Innovation**: Complete independent implementation with built-in memory access tracking, providing full 4917 processor compatibility while enabling advanced program analysis and optimization capabilities.R