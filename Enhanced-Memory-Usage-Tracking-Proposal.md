# Proposal: Enhanced Memory Usage Tracking for Advanced WildcardPattern Optimization

## Problem Statement

Current optimization is too simplistic because it doesn't distinguish how memory locations are used during execution. We need to track whether each memory location was accessed as:
1. **Instruction** - Fetched and executed by the processor
2. **Operand** - Read as data for instruction parameters
3. **Both** - Used in different contexts during execution

This enables much more sophisticated optimizations, such as optimizing print operands by output length when they're only used as operands.

## Core Insight Examples

### Example 1: Print Operand Optimization
```haskell
-- Program: [8, 5, 0] -- PRINT 5, HALT
-- Current: [Required 8, Required 5, Required 0]
-- Enhanced: [Required 8, AnyOf [0..9], Required 0]  -- Same output length as 5
```

### Example 2: Mixed Usage Prevention
```haskell
-- Program: [8, 5, 13, 5, 0] -- PRINT 5, JMP 5, HALT (position 5 used as both operand and instruction target)
-- Must be: [Required 8, Required 5, Required 13, Required 5, Required 0]  -- No optimization of position 5
```

## Proposed TrackedDevice Enhancements

### Enhanced Data Structure

```haskell
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
    , r0ContainsCombination :: Bool     -- True if R0 contains ADD/SUB result
    -- NEW FIELDS:
    , instructionLocations :: Set Int   -- Positions accessed as instructions (PC reads)
    , operandLocations :: Set Int       -- Positions accessed as operands (instruction parameter reads)
    } deriving (Show, Eq)

-- NOTE: accessedLocations field REMOVED - now derived from instructionLocations ∪ operandLocations
```

### New and Updated Accessor Functions

```haskell
getInstructionLocations :: TrackedDevice -> Set Int
getInstructionLocations = instructionLocations

getOperandLocations :: TrackedDevice -> Set Int  
getOperandLocations = operandLocations

-- UPDATED: Now derived from the two specific location sets
getAccessedLocations :: TrackedDevice -> Set Int
getAccessedLocations device = 
    instructionLocations device `Set.union` operandLocations device

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
```

### Updated createTrackedDevice Function

```haskell
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
        -- NEW FIELDS:
        , instructionLocations = Set.empty
        , operandLocations = Set.empty
        }
```

## Enhanced Instruction Execution Tracking

### Core Tracking Strategy

Every instruction execution needs to track:
1. **PC reads** → Add to `instructionLocations`
2. **Operand reads** → Add to `operandLocations`
3. **All reads** → Automatically available via `getAccessedLocations` (derived from union)

### Updated executeInstructionWithTracking Function

```haskell
executeInstructionWithTracking :: Byte -> TrackedDevice -> (TrackedDevice, Set Int)
executeInstructionWithTracking instruction device = 
    let currentPc = fromIntegral (pc device)
        -- Track that current PC was accessed as an instruction
        deviceWithInstrTracking = device { instructionLocations = Set.insert currentPc (instructionLocations device) }
    in case instruction of
        -- Two-byte instructions need operand tracking
        8 -> -- PRINT
            let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                operandValue = memory device ! operandLoc
                newOutputLength = outputLength device + if operandValue <= 9 then 1 else 2
                -- Track operand access
                deviceWithOperandTracking = deviceWithInstrTracking { operandLocations = Set.insert operandLoc (operandLocations deviceWithInstrTracking) }
                newDevice = deviceWithOperandTracking { outputLength = newOutputLength, pc = (pc device + 2) `mod` 16 }
                accesses = Set.fromList [currentPc, operandLoc]  -- Return for compatibility with existing interface
            in (newDevice, accesses)
            
        9 -> -- LOAD R0
            let operandLoc = fromIntegral ((pc device + 1) `mod` 16)
                addressValue = memory device ! operandLoc
                dataLoc = fromIntegral addressValue
                dataValue = memory device ! dataLoc
                -- Track both operand and data accesses
                deviceWithOperandTracking = deviceWithInstrTracking { operandLocations = Set.insert operandLoc (operandLocations deviceWithInstrTracking) }
                newDevice = deviceWithOperandTracking { r0 = dataValue, pc = (pc device + 2) `mod` 16 }
                accesses = Set.fromList [currentPc, operandLoc, dataLoc]
            in (newDevice, accesses)
            
        -- Similar updates for all two-byte instructions (9, 10, 11, 12, 13, 14, 15)
        
        -- Single-byte instructions only track PC access
        _ -> let newDevice = deviceWithInstrTracking { pc = (pc device + 1) `mod` 16 }
                 accesses = Set.singleton currentPc
             in (newDevice, accesses)
```

## Enhanced WildcardPattern Logic

### New Memory Usage Analysis

```haskell
data MemoryUsageType = 
    InstructionOnly     -- Only accessed as instruction
  | OperandOnly         -- Only accessed as operand
  | MixedUsage          -- Used as both instruction and operand
  | Unused              -- Never accessed
  deriving (Show, Eq)

data EnhancedMemoryAnalysis = EnhancedMemoryAnalysis
    { memoryUsageTypes :: [MemoryUsageType]  -- Usage type for each of 16 memory positions
    , operandOutputOptimizations :: [(Int, [Byte])]  -- Position and equivalent output-length values
    } deriving (Show, Eq)

-- Enhanced program analysis
data EnhancedProgramAnalysis = EnhancedProgramAnalysis
    { programOriginal :: [Byte]
    , deadRegisterPositions :: [Int]  
    , registerAnalysis :: DeadOperationAnalysis
    , trackedDevice :: TrackedDevice
    , memoryAnalysis :: EnhancedMemoryAnalysis  -- NEW
    } deriving (Show)

analyzeMemoryUsage :: TrackedDevice -> EnhancedMemoryAnalysis
analyzeMemoryUsage device = 
    let instrLocs = getInstructionLocations device
        operandLocs = getOperandLocations device
        mixedLocs = getMixedUsageLocations device
        instrOnlyLocs = getInstructionOnlyLocations device
        operandOnlyLocs = getOperandOnlyLocations device
        
        -- Classify each memory position
        usageTypes = map (classifyPosition instrLocs operandLocs mixedLocs) [0..15]
        
        -- Identify operand optimization opportunities
        operandOptimizations = findOperandOptimizations device operandOnlyLocs
        
    in EnhancedMemoryAnalysis usageTypes operandOptimizations

classifyPosition :: Set Int -> Set Int -> Set Int -> Int -> MemoryUsageType
classifyPosition instrLocs operandLocs mixedLocs pos
    | pos `Set.member` mixedLocs = MixedUsage
    | pos `Set.member` instrLocs = InstructionOnly  
    | pos `Set.member` operandLocs = OperandOnly
    | otherwise = Unused
```

### Operand Output Length Optimization

```haskell
-- Find operand positions that can be optimized by output length
findOperandOptimizations :: TrackedDevice -> Set Int -> [(Int, [Byte])]
findOperandOptimizations device operandOnlyLocs = 
    let program = Vector.toList (memory device)
        optimizations = mapMaybe (analyzeOperandPosition program) (Set.toList operandOnlyLocs)
    in optimizations

analyzeOperandPosition :: [Byte] -> Int -> Maybe (Int, [Byte])
analyzeOperandPosition program pos = 
    if pos > 0 && pos < length program
    then case program !! (pos - 1) of
        8 -> -- PRINT instruction operand
            let currentValue = program !! pos
                currentOutputLength = if currentValue <= 9 then 1 else 2
                equivalentValues = if currentOutputLength == 1 
                                  then [0..9]     -- All single-digit outputs
                                  else [10..15]   -- All double-digit outputs
            in Just (pos, equivalentValues)
        _ -> Nothing  -- Other instruction operands aren't easily optimizable
    else Nothing

-- Output length categories
singleCharOutput :: [Byte]
singleCharOutput = [0..9]

doubleCharOutput :: [Byte] 
doubleCharOutput = [10..15]
```

### Enhanced Classification Logic

```haskell
-- Enhanced memory position classification
classifyEnhancedMemoryPosition :: EnhancedProgramAnalysis -> Int -> OptimizedInstruction  
classifyEnhancedMemoryPosition analysis pos 
    | pos >= 16 = error "Invalid memory position"
    | otherwise = 
        let usageType = (memoryUsageTypes (memoryAnalysis analysis)) !! pos
            program = programOriginal analysis
            operandOptimizations = operandOutputOptimizations (memoryAnalysis analysis)
        in case usageType of
            Unused -> Wildcard
            MixedUsage -> Required (program !! pos)  -- Must be exact due to dual usage
            InstructionOnly -> 
                if pos `elem` deadRegisterPositions analysis 
                then classifyDeadRegisterPosition (program !! pos)
                else Required (program !! pos)
            OperandOnly -> 
                case lookup pos operandOptimizations of
                    Just equivalentValues -> AnyOf equivalentValues  -- Optimize by output length
                    Nothing -> Required (program !! pos)            -- Default to required
```

## Implementation Plan

### Phase 1: TrackedDevice Enhancement
1. **Add new fields** to TrackedDevice data structure
2. **Update createTrackedDevice** with new field initialization
3. **Add accessor functions** for instruction/operand location analysis
4. **Update module exports** to include new functions

### Phase 2: Execution Tracking
1. **Enhance executeInstructionWithTracking** for all 16 instructions
2. **Track PC reads** as instruction accesses
3. **Track operand reads** for two-byte instructions (8-15)
4. **Track data reads** for load/store operations
5. **Update all instruction cases** to maintain dual tracking

### Phase 3: WildcardPattern Integration
1. **Create EnhancedMemoryAnalysis** data structures
2. **Implement analyzeMemoryUsage** function
3. **Add operand output optimization** logic
4. **Update classifyMemoryPosition** to use enhanced analysis
5. **Modify optimizeProgram** to use enhanced classification

### Phase 4: Testing & Validation
1. **Update all existing tests** to expect enhanced behavior
2. **Add tests for mixed usage scenarios** (instruction + operand)
3. **Add tests for operand optimization** (print output length)
4. **Add tests for complex programs** with multiple usage patterns
5. **Validate performance** doesn't degrade significantly

## Expected Benefits

### Advanced Optimization Examples

```haskell
-- Example 1: Print operand optimization
-- Program: [8, 5, 8, 12, 0] -- PRINT 5, PRINT 12, HALT
-- Enhanced: [Required 8, AnyOf [0..9], Required 8, AnyOf [10..15], Required 0]
-- Both operands optimized by output length

-- Example 2: Mixed usage prevention  
-- Program: [8, 5, 13, 5, 0] -- PRINT 5, JMP 5, HALT  
-- Enhanced: [Required 8, Required 5, Required 13, Required 5, Required 0]
-- Position 5 used as both operand and jump target, so must be Required

// Example 3: Complex optimization
// Program: [8, 7, 3, 9, 12, 0] -- PRINT 7, INC R0, LOAD R0 from 12, HALT
// Enhanced: [Required 8, AnyOf [0..9], AnyOf regOps, Required 9, Required 12, Required 0]
// Position 1 (print operand) optimized, position 2 (dead register) optimized, position 4 (load address) required
```

### Performance Impact
- **Search Space Reduction**: Even more dramatic than current optimization
- **Accuracy**: Prevents incorrect optimization of dual-usage positions  
- **Flexibility**: Enables new categories of optimization (output length, address patterns, etc.)

## Testing Strategy

### Critical Test Cases

```haskell
-- Test mixed usage detection
testMixedUsage = [8, 5, 13, 5, 0]  -- Position 5 used as operand and instruction target

-- Test operand-only optimization  
testOperandOptim = [8, 7, 8, 12, 0]  -- Both operands only used as operands

-- Test complex program
testComplex = [9, 12, 11, 5, 13, 8, 8, 3, 0]  -- Mix of loads, stores, jumps, prints
```

This enhanced tracking enables much more sophisticated optimization while preventing incorrect optimization of memory locations with dual usage.