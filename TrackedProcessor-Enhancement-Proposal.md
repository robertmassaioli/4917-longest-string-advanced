# TrackedProcessor.hs Enhancement Proposal: Register Consumption Tracking

## Overview

This proposal outlines modifications to `TrackedProcessor.hs` to track whether any instructions were executed that "consumed" R0 or R1 register values. This tracking will enable Dead Register Operation Detection as outlined in PatternAnalysisThoughts.md.

## Current TrackedProcessor.hs Analysis

The current `TrackedProcessor.hs` provides:
- `TrackedDevice` data type with memory access tracking (`accessedLocations`)
- Complete independent processor implementation with all 16 instructions
- `executeInstructionWithTracking` function that tracks memory reads
- Validation and accessor functions

## Proposed Enhancement: Register Consumption Tracking

### Core Concept

Add tracking to determine if R0/R1 register values were ever used for observable effects during program execution.

**Consuming Instructions** (use register values for observable effects):
- `11` (STORE R0): Uses R0 value to modify memory
- `12` (STORE R1): Uses R1 value to modify memory  
- `14` (JZ): Uses R0 value for control flow decision
- `15` (JNZ): Uses R0 value for control flow decision

**Non-consuming Instructions**: All other instructions that manipulate registers but don't "use" their values.

## Proposed Code Changes

### 1. Enhanced TrackedDevice Data Structure

```haskell
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
    -- NEW FIELDS:
    , r0WasConsumed :: Bool             -- True if R0 was ever consumed
    , r1WasConsumed :: Bool             -- True if R1 was ever consumed
    , r0ContainsCombination :: Bool     -- True if R0 contains result of ADD/SUB using both registers
    } deriving (Show, Eq)
```

### 2. Updated createTrackedDevice Function

```haskell
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
        , accessedLocations = Set.empty
        -- NEW FIELDS:
        , r0WasConsumed = False
        , r1WasConsumed = False
        , r0ContainsCombination = False
        }
```

### 3. New Accessor Functions

```haskell
-- New accessor functions for register consumption
getR0WasConsumed :: TrackedDevice -> Bool
getR0WasConsumed = r0WasConsumed

getR1WasConsumed :: TrackedDevice -> Bool
getR1WasConsumed = r1WasConsumed

getR0ContainsCombination :: TrackedDevice -> Bool
getR0ContainsCombination = r0ContainsCombination
```

### 4. Helper Function for Register Consumption Classification

```haskell
-- | Determine which registers an instruction consumes, accounting for combination tracking
classifyRegisterConsumption :: Byte -> TrackedDevice -> (Bool, Bool)  -- (consumesR0, consumesR1)
classifyRegisterConsumption instruction device = case instruction of
    11 -> (True, r0ContainsCombination device)  -- STORE R0: uses R0, and R1 if R0 contains combination
    12 -> (False, True)                         -- STORE R1: uses R1 directly
    14 -> (True, r0ContainsCombination device)  -- JZ: uses R0, and R1 if R0 contains combination  
    15 -> (True, r0ContainsCombination device)  -- JNZ: uses R0, and R1 if R0 contains combination
    _  -> (False, False)                        -- All other instructions don't consume register values
```

### 5. Enhanced executeInstructionWithTracking Function

The existing `executeInstructionWithTracking` function would be modified to track register consumption. The return type becomes:

```haskell
-- Execute single instruction with memory access tracking and register consumption
executeInstructionWithTracking :: Byte -> TrackedDevice -> (TrackedDevice, Set Int)
```

**Key changes** in the instruction execution cases:

```haskell
-- Example for ADD (1) - Track combination but don't consume
1 -> let newR0 = (r0 device + r1 device) `mod` 16
         -- R0 now contains a combination of both registers
         combinationDevice = device { r0ContainsCombination = True }
     in (combinationDevice { r0 = newR0, pc = (pc device + 1) `mod` 16 }, Set.empty)

-- Example for SUB (2) - Track combination but don't consume  
2 -> let newR0 = (r0 device - r1 device) `mod` 16
         -- R0 now contains a combination of both registers
         combinationDevice = device { r0ContainsCombination = True }
     in (combinationDevice { r0 = newR0, pc = (pc device + 1) `mod` 16 }, Set.empty)

-- Example for STORE R0 (11)  
11 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
          address = memory device ! operandLoc
          newMemory = memory device // [(fromIntegral address, r0 device)]
          -- Classify consumption based on combination tracking
          (consumesR0, consumesR1) = classifyRegisterConsumption 11 device
          consumedDevice = device { r0WasConsumed = r0WasConsumed device || consumesR0
                                  , r1WasConsumed = r1WasConsumed device || consumesR1 }
          newDevice = consumedDevice { memory = newMemory, pc = (pc device + 2) `mod` 16 }
          accesses = Set.singleton operandLoc
      in (newDevice, accesses)

-- Example for STORE R1 (12)
12 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
          address = memory device ! operandLoc
          newMemory = memory device // [(fromIntegral address, r1 device)]
          -- R1 is always consumed directly
          consumedDevice = device { r1WasConsumed = True }
          newDevice = consumedDevice { memory = newMemory, pc = (pc device + 2) `mod` 16 }
          accesses = Set.singleton operandLoc
      in (newDevice, accesses)

-- Example for JZ (14)
14 -> let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
          address = memory device ! operandLoc
          newPc = if r0 device == 0 then address `mod` 16 else (pc device + 2) `mod` 16
          -- Classify consumption based on combination tracking
          (consumesR0, consumesR1) = classifyRegisterConsumption 14 device
          consumedDevice = device { r0WasConsumed = r0WasConsumed device || consumesR0
                                  , r1WasConsumed = r1WasConsumed device || consumesR1 }
          newDevice = consumedDevice { pc = newPc }
          accesses = Set.singleton operandLoc
      in (newDevice, accesses)

-- Other R0-modifying instructions preserve the combination flag
-- The combination flag is a latch - once set, it stays set for the entire program execution
```

### 6. Updated Module Exports

```haskell
module TrackedProcessor
    ( TrackedDevice(..)
    , ValidationError(..)
    , ErrorType(..)
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
    -- NEW EXPORTS:
    , getR0WasConsumed
    , getR1WasConsumed
    , getR0ContainsCombination
    , classifyRegisterConsumption
    ) where
```

## Implementation Strategy

### Modification Approach

1. **Add new fields** to `TrackedDevice` data structure
2. **Update `createTrackedDevice`** to initialize new fields 
3. **Add new accessor functions** for register consumption
4. **Implement `classifyRegisterConsumption`** helper function
5. **Modify each relevant instruction case** in `executeInstructionWithTracking` to set consumption flags
6. **Update module exports** to include new functions
7. **Maintain backward compatibility** - all existing functionality unchanged

### Specific Instruction Modifications

These instruction cases need modification:

**Combination Tracking Instructions:**
- **Instruction 1 (ADD)**: Set `r0ContainsCombination = True`
- **Instruction 2 (SUB)**: Set `r0ContainsCombination = True`

**Consumption Instructions (with combination awareness):**
- **Instruction 11 (STORE R0)**: Set `r0WasConsumed` and `r1WasConsumed` if R0 contains combination
- **Instruction 12 (STORE R1)**: Set `r1WasConsumed`
- **Instruction 14 (JZ)**: Set `r0WasConsumed` and `r1WasConsumed` if R0 contains combination
- **Instruction 15 (JNZ)**: Set `r0WasConsumed` and `r1WasConsumed` if R0 contains combination

**Note on Other R0-Modifying Instructions:**
- Instructions 3, 5, 9 (INC R0, DEC R0, LOAD R0) preserve the `r0ContainsCombination` flag
- The combination flag acts as a latch - once set by ADD/SUB, it remains true for the entire program execution
- This ensures that any future consumption of R0 will correctly identify R1 as also being consumed

## Usage for Dead Register Detection

With this enhancement, dead register detection becomes straightforward:

```haskell
-- Example usage in WildcardPattern module
analyzeDeadRegisters :: TrackedDevice -> (Bool, Bool)  -- (r0HasDeadOps, r1HasDeadOps)
analyzeDeadRegisters device = 
    let r0Used = getR0WasConsumed device
        r1Used = getR1WasConsumed device
        -- If registers were never consumed, all manipulating operations were dead
    in (not r0Used, not r1Used)
```

## Benefits

1. **Minimal Changes**: Only adds two boolean fields and updates consuming instruction cases
2. **Zero Performance Overhead**: Simple boolean flag updates during execution  
3. **Backward Compatible**: No changes to existing function signatures or behavior
4. **Complete Detection**: Tracks consumption throughout entire program execution
5. **Simple Integration**: Easy to use in pattern analysis modules

## Testing Strategy

### Unit Tests for New Functionality
```haskell
-- Test that non-consuming operations don't set flags
testNoConsumption = do
    let device = createTrackedDevice [3, 4, 5, 6, 0] -- INC R0, INC R1, DEC R0, DEC R1, HALT
        result = runTrackedProgram device 100
    assertEqual False (getR0WasConsumed result)
    assertEqual False (getR1WasConsumed result)

-- Test that consuming operations do set flags  
testR0Consumption = do
    let device = createTrackedDevice [3, 11, 0, 0] -- INC R0, STORE R0, HALT
        result = runTrackedProgram device 100
    assertEqual True (getR0WasConsumed result)
    assertEqual False (getR1WasConsumed result)

-- Test both registers consumed via combination
testBothConsumption = do
    let device = createTrackedDevice [3, 4, 1, 11, 0, 0] -- INC R0, INC R1, ADD, STORE R0, HALT
        result = runTrackedProgram device 100
    assertEqual True (getR0WasConsumed result)
    assertEqual True (getR1WasConsumed result)  -- R1 consumed via combination in R0

-- Test combination latch behavior
testCombinationLatch = do
    let device = createTrackedDevice [3, 4, 1, 3, 11, 0, 0] -- INC R0, INC R1, ADD, INC R0, STORE R0, HALT
        result = runTrackedProgram device 100
    assertEqual True (getR0WasConsumed result)
    assertEqual True (getR1WasConsumed result)  -- R1 still consumed despite R0 being modified after ADD
```

### Integration Tests
- Verify existing functionality unchanged
- Test all 16 instructions for correct consumption classification
- Validate that memory access tracking still works correctly

## Questions for Review

1. **Is the two-boolean approach sufficient, or would step-by-step consumption tracking be more valuable?**

2. **Should the consumption flags be cumulative (once set, always true) or should there be a way to reset them?**

3. **Are there any edge cases in the instruction classification that need consideration?**

4. **Should this enhancement be implemented in phases or all at once?**