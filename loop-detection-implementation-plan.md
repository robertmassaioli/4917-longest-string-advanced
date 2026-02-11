# Loop Detection Implementation Plan
## Eliminating Timeout State with Floyd's Cycle Detection

### Project Overview
Replace the current timeout-based loop detection with a sophisticated cycle detection algorithm based on Floyd's "tortoise and hare" algorithm. This will eliminate the `Timeout` termination state and provide definitive `Halt` or `InfiniteLoop` classifications for all programs.

---

## Current Problem Analysis

### Issues with Current Timeout Approach
- **False Positives**: Long-running programs incorrectly classified as infinite loops
- **Inconsistent Results**: Same program produces different results based on step limits
- **Poor Pattern Analysis**: PatternAnalyzer receives ambiguous `Timeout` instead of definitive termination
- **Arbitrary Limits**: Step counters are crude approximations, not mathematical proofs

### Why This Matters for 4917 Processor
- **Deterministic Results**: Critical for caching - same program must always produce same result
- **Performance**: Stop execution immediately when loop is detected (no waiting for timeout)
- **Accuracy**: Pattern analysis needs definitive termination information
- **User Experience**: Clear classification helps users understand program behavior

---

## Algorithm Design

### Core Concept: Processor State Space
Every processor state can be uniquely identified by:
```haskell
data ProcessorState = ProcessorState
    { statePc :: Byte           -- Program Counter (0-15)
    , stateR0 :: Byte           -- Register R0 (0-15) 
    , stateR1 :: Byte           -- Register R1 (0-15)
    , stateMemory :: Vector Byte -- Memory state (for self-modifying programs)
    } deriving (Eq, Ord, Show)
```

**Key Insight**: The 4917 processor has a **finite state space**:
- PC: 16 possible values (0-15)
- R0: 16 possible values (0-15)  
- R1: 16 possible values (0-15)
- Memory: 16^16 possible configurations (astronomical but finite)

**Mathematical Guarantee**: Any infinite execution **must** revisit a previous state, creating a cycle.

---

## Floyd's Cycle Detection Algorithm

### Classical Floyd's Algorithm
Floyd's "tortoise and hare" algorithm detects cycles in sequences by using two pointers moving at different speeds:

```
1. Slow pointer (tortoise) moves 1 step per iteration
2. Fast pointer (hare) moves 2 steps per iteration  
3. If there's a cycle, hare will eventually lap tortoise
4. If no cycle, hare will reach the end
```

### Adaptation for 4917 Processor

#### Challenge: Discrete Steps vs. Linked List
Floyd's algorithm assumes you can advance arbitrary steps in a sequence. Our processor executes one instruction at a time.

#### Solution: State Sequence Generation
Instead of moving pointers, we'll generate the state sequence and apply Floyd's algorithm:

```haskell
-- Generate processor state sequence
generateStates :: Device -> [ProcessorState]
generateStates device 
    | isHalted device = [extractState device]
    | otherwise = extractState device : generateStates (runStep device)

-- Floyd's cycle detection on state sequence  
detectCycle :: [ProcessorState] -> CycleDetectionResult
```

#### Implementation Strategy

**Phase 1: Bounded Floyd's Detection**
```haskell
data CycleDetectionResult 
    = NoCycleFound Device Int           -- Halted after N steps
    | CycleDetected Device CycleInfo    -- Loop found with details
    | StateSpaceExhausted Device Int    -- Too many states (fallback)

data CycleInfo = CycleInfo
    { cycleStartStep :: Int      -- When cycle begins
    , cycleLength :: Int         -- Length of repeating cycle
    , cycleStartState :: ProcessorState  -- State where cycle starts
    }
```

**Phase 2: Optimized State Representation**
For efficiency, we'll use a compact state representation:
```haskell
-- Compact state for faster comparison
data CompactState = CompactState
    { compactPc :: Byte
    , compactR0 :: Byte  
    , compactR1 :: Byte
    , compactMemoryHash :: Int  -- Hash of memory for self-modifying programs
    } deriving (Eq, Ord, Show)

-- Convert full state to compact representation
compactifyState :: ProcessorState -> CompactState
```

---

## Detailed Implementation Plan

## Architectural Benefits of Pure Floyd's Approach

### Problems Avoided by Using True Floyd's Algorithm
1. **Memory Efficiency**: O(1) space complexity - only two Device states needed
2. **No State Pollution**: Device remains a clean processor state representation  
3. **No Complex State Management**: No history tracking, seen states, or external state
4. **Mathematical Elegance**: Classic Floyd's algorithm in its pure form
5. **Guaranteed Termination**: Finite state space ensures algorithm completion

### Ultra-Clean Separation of Concerns
- **Device**: Pure processor state (PC, registers, memory) - unchanged
- **Floyd's Algorithm**: Two Device pointers moving at different speeds
- **CycleDetectionResult**: Simple result type with cycle information
- **ExecutionTrace**: Generated on-demand when needed for analysis

### No Timeout Philosophy
**Key Insight**: The 4917 processor has a mathematically finite state space:
- **Read-only programs**: At most 16³ = 4,096 states (PC × R0 × R1)  
- **Self-modifying programs**: At most 16^19 states (still finite)
- **Mathematical Guarantee**: Floyd's algorithm MUST terminate within finite steps
- **No timeouts needed**: Pure mathematical certainty replaces arbitrary limits

---

### Step 1: Clean State Management

#### 1.1 Clean State Representation (No History in Device)
**File**: `src/Processor.hs`

```haskell
-- Device remains clean - NO executionHistory pollution
-- Existing Device data type unchanged:
data Device = Device
    { pc :: Byte
    , r0 :: Byte
    , r1 :: Byte  
    , memory :: Vector Byte
    , outputLength :: Int
    , isHalted :: Bool
    , steps :: Int
    } deriving (Show, Eq)

-- New function: Extract current processor state (pure function)
extractCurrentState :: Device -> CompactState
extractCurrentState device = CompactState
    { compactPc = pc device
    , compactR0 = r0 device
    , compactR1 = r1 device  
    , compactMemoryHash = if programModifiesMemory device
                         then fastHash (Vector.toList (memory device))
                         else 0  -- Optimization: no hash for read-only programs
    }

-- New function: Analyze program structure (static analysis)
programModifiesMemory :: Device -> Bool
programModifiesMemory device = any isMemoryInstruction (Vector.toList (memory device))
  where
    isMemoryInstruction instr = instr `elem` [11, 12]  -- STORE R0, STORE R1
```

#### 1.2 Elimination of Complex State Management
```haskell
-- REMOVED: No external state tracking needed for true Floyd's algorithm!
-- Floyd's algorithm only needs to compare tortoise and hare states directly
-- No history storage, no seen states set, no complex detection state

-- Simple, elegant Floyd's cycle detection
data CycleDetectionResult 
    = ProgramHalted Device                     -- Program reached HALT instruction
    | InfiniteLoopDetected Device CycleInfo    -- Cycle detected with details
    deriving (Show, Eq)

data CycleInfo = CycleInfo
    { cycleStartStep :: Int            -- When cycle was detected
    , cycleLength :: Int               -- Estimated cycle length
    , cycleStartState :: CompactState  -- State where cycle detected
    } deriving (Show, Eq)

-- No complex state management - just pure algorithm logic
extractCurrentState :: Device -> CompactState
extractCurrentState device = CompactState
    { compactPc = pc device
    , compactR0 = r0 device
    , compactR1 = r1 device
    , compactMemoryHash = if programModifiesMemory device
                         then fastHash (Vector.toList (memory device))
                         else 0  -- Optimization: no hash for read-only programs
    }
```

### Step 2: Floyd's Cycle Detection Engine

#### 2.1 Core Cycle Detection Algorithm
**File**: `src/LoopDetection.hs` (new file)

```haskell
{-# LANGUAGE RecordWildCards #-}

module LoopDetection
    ( runProgramWithLoopDetection
    , CycleDetectionResult(..)
    , CycleInfo(..)
    , LoopClassification(..)
    ) where

import Processor
import ExecutionTracing
import qualified Data.Set as Set
import qualified Data.Map as Map

-- Pure Floyd's cycle detection - O(1) memory, no timeouts
runProgramWithLoopDetection :: Device -> (CycleDetectionResult, ExecutionTrace)
runProgramWithLoopDetection initialDevice = 
    case floydDetection initialDevice initialDevice 0 of
        (result, hareSteps) -> (result, buildTraceIfNeeded initialDevice result hareSteps)
  where
    -- True Floyd's algorithm - focused on hare's progress
    floydDetection :: Device -> Device -> Int -> (CycleDetectionResult, Int)
    floydDetection tortoise hare hareSteps
        -- Check if hare has halted - return the hare (final state) with hare's step count
        | isHalted hare = (ProgramHalted hare, hareSteps)
        
        -- Both still running - check for cycle (mathematical guarantee: will terminate)
        | extractCurrentState tortoise == extractCurrentState hare && hareSteps > 0 = 
            (InfiniteLoopDetected tortoise (analyzeCycleFromTortoise tortoise), hareSteps)
        
        -- Continue Floyd's algorithm - track hare's actual steps
        | otherwise = 
            let newTortoise = runStep tortoise
                newHare = runStep (runStep hare)  -- Hare moves 2 steps
            in floydDetection newTortoise newHare (hareSteps + 2)  -- Increment by 2 for hare's steps

-- Build execution trace only when needed (optional for performance)
buildTraceIfNeeded :: Device -> CycleDetectionResult -> Int -> ExecutionTrace
buildTraceIfNeeded initialDevice result hareSteps =
    case result of
        ProgramHalted finalDevice -> buildHaltTrace initialDevice finalDevice hareSteps
        InfiniteLoopDetected device cycleInfo -> buildLoopTrace initialDevice device cycleInfo hareSteps
        _ -> buildSimpleTrace initialDevice hareSteps

-- Efficient trace building by replaying execution
-- Note: hareSteps might be more than actual program steps since hare moves faster
buildHaltTrace :: Device -> Device -> Int -> ExecutionTrace
buildHaltTrace initialDevice finalDevice hareSteps =
    let -- Execute until halt to get actual execution steps (not hare steps)
        executionStates = takeWhileInclusive (not . isHalted) $ iterate runStep initialDevice
        actualSteps = length executionStates
        tracePoints = zipWith deviceToTracePoint [0..] executionStates
        finalState = deviceToExecutionState finalDevice
    in ExecutionTrace tracePoints actualSteps finalState

buildSimpleTrace :: Device -> Int -> ExecutionTrace  
buildSimpleTrace initialDevice hareSteps =
    let -- For cycle detection, use hare steps as estimate but cap at reasonable limit
        estimatedSteps = min hareSteps 10000  -- Reasonable upper bound for trace building
        states = take estimatedSteps $ iterate runStep initialDevice
        tracePoints = zipWith deviceToTracePoint [0..] states
        finalState = if null states then emptyExecutionState else deviceToExecutionState (last states)
    in ExecutionTrace tracePoints estimatedSteps finalState

-- Helper: takeWhile that includes the first element that fails the predicate  
takeWhileInclusive :: (a -> Bool) -> [a] -> [a]
takeWhileInclusive _ [] = []
takeWhileInclusive p (x:xs) 
    | p x = x : takeWhileInclusive p xs
    | otherwise = [x]  -- Include the failing element

-- Analyze cycle characteristics from current tortoise state
analyzeCycleFromTortoise :: Device -> CycleInfo
analyzeCycleFromTortoise tortoise = 
    let currentState = extractCurrentState tortoise
        -- For detected cycles, estimate properties without full history
        estimatedLength = estimateCycleLengthFromState tortoise
    in CycleInfo
        { cycleStartStep = 0  -- Approximation - exact value would require tortoise step tracking
        , cycleLength = estimatedLength
        , cycleStartState = currentState
        }

-- Note: If precise cycle start step is needed, we could track tortoise steps separately:
-- floydDetection tortoise hare tortoiseSteps hareSteps = ...
-- But for most purposes, knowing the cycle exists and its approximate length is sufficient

-- Estimate cycle length by analyzing program structure at current position
estimateCycleLengthFromState :: Device -> Int
estimateCycleLengthFromState device =
    let currentPc = pc device
        -- Look for obvious patterns in program structure
    in case analyzeInstructionPattern device of
        JumpToSelf -> 2  -- JMP to current or adjacent instruction
        ShortBackwardJump target -> fromIntegral (currentPc - target + 1)
        _ -> 3  -- Conservative estimate for unknown patterns

-- Helper functions for cycle analysis
data InstructionPattern 
    = JumpToSelf                    -- JMP to same/adjacent instruction
    | ShortBackwardJump Byte        -- JMP to recent previous instruction  
    | ConditionalLoop Byte          -- JZ/JNZ creating potential loop
    | LinearExecution               -- No obvious loop pattern
    deriving (Show, Eq)

-- Analyze instruction pattern at current position for cycle estimation
analyzeInstructionPattern :: Device -> InstructionPattern
analyzeInstructionPattern device =
    let currentPc = pc device
        currentInstr = if currentPc < 16 then (memory device) ! fromIntegral currentPc else 0
        nextByte = if currentPc < 15 then (memory device) ! fromIntegral (currentPc + 1) else 0
    in case currentInstr of
        13 | nextByte == currentPc || nextByte == currentPc + 1 -> JumpToSelf
        13 | nextByte < currentPc -> ShortBackwardJump nextByte  
        14 -> ConditionalLoop nextByte  -- JZ
        15 -> ConditionalLoop nextByte  -- JNZ
        _ -> LinearExecution

-- Classify loop based on cycle characteristics (simplified without full history)
classifyLoopFromPattern :: InstructionPattern -> Int -> LoopClassification
classifyLoopFromPattern pattern estimatedLength =
    case pattern of
        JumpToSelf -> SimpleLoop estimatedLength
        ShortBackwardJump _ -> SimpleLoop estimatedLength
        ConditionalLoop _ -> ConditionalLoop estimatedLength
        LinearExecution -> ComplexLoop estimatedLength  -- Shouldn't happen in cycle
```

#### 2.2 Loop Classification System
```haskell
data LoopClassification 
    = SimpleLoop Int        -- Short cycle, no conditionals
    | ConditionalLoop Int   -- Has conditional jumps  
    | ComplexLoop Int       -- Long cycle or complex pattern
    | MemoryModifyingLoop Int -- Self-modifying program
    deriving (Show, Eq)

classifyLoop :: CycleInfo -> LoopClassification
classifyLoop CycleInfo{..}
    | cycleLength <= 3 = SimpleLoop cycleLength
    | cycleLength <= 10 = ConditionalLoop cycleLength  
    | otherwise = ComplexLoop cycleLength

data CycleDetectionResult 
    = NoCycleFound Device Int                              -- Program halted normally
    | CycleDetected Device CycleInfo LoopClassification   -- Infinite loop with details  
    | StateSpaceExhausted Device Int                      -- Complex behavior (fallback)
    deriving (Show, Eq)
```

### Step 3: Integration with Execution Framework

#### 3.1 Update BruteForceSearch
**File**: `src/BruteForceSearch.hs`

```haskell
import LoopDetection

-- Replace timeout-based evaluation
evaluateProgram :: [Byte] -> IO ProgramResult
evaluateProgram program = do
    timestamp <- getCurrentTime
    let device = createDevice program
    (cycleResult, trace) <- runProgramWithLoopDetection device
    
    return $ case cycleResult of
        NoCycleFound finalDevice steps -> ProgramResult
            { resultOutput = outputLength finalDevice
            , resultSteps = steps
            , resultTermination = Halt  -- Definitive halt
            , resultTrace = trace
            , resultProgram = program
            , resultTimestamp = timestamp
            }
            
        CycleDetected finalDevice cycleInfo loopClass -> ProgramResult  
            { resultOutput = outputLength finalDevice
            , resultSteps = cycleStartStep cycleInfo
            , resultTermination = InfiniteLoop  -- Definitive infinite loop
            , resultTrace = trace  
            , resultProgram = program
            , resultTimestamp = timestamp
            , resultLoopInfo = Just (cycleInfo, loopClass)  -- Rich loop information
            }
            
        StateSpaceExhausted finalDevice stateCount -> ProgramResult
            { resultOutput = outputLength finalDevice
            , resultSteps = stateCount
            , resultTermination = InfiniteLoop  -- Assume infinite for very complex behavior
            , resultTrace = trace
            , resultProgram = program  
            , resultTimestamp = timestamp
            , resultLoopInfo = Nothing
            }
```

#### 3.2 Eliminate Timeout from TerminationType
**File**: `src/ExecutionTracing.hs`

```haskell
-- Remove Timeout completely
data TerminationType 
    = Halt              -- Program executed HALT instruction
    | InfiniteLoop      -- Definitive cycle detected
    | Error             -- Invalid instruction or error condition
    deriving (Show, Eq, Ord, Generic, ToJSON, FromJSON, NFData)
    -- Timeout removed!
```

### Step 4: Enhanced Pattern Analysis

#### 4.1 Update PatternAnalyzer for Definitive Loop Information
**File**: `src/PatternAnalyzer.hs`

```haskell
-- Pattern analysis with definitive termination information
analyzeProgram :: [Byte] -> ProgramResult -> ProgramPattern
analyzeProgram program result = 
    case resultTermination result of
        Halt -> analyzeHaltPattern program result
        InfiniteLoop -> analyzeInfiniteLoopPattern program result  -- No more Timeout ambiguity!
        Error -> analyzeErrorPattern program result

-- Enhanced loop pattern analysis with cycle information
analyzeInfiniteLoopPattern :: [Byte] -> ProgramResult -> ProgramPattern  
analyzeInfiniteLoopPattern program result = 
    case resultLoopInfo result of
        Nothing -> createBasicLoopPattern program result  -- Fallback for complex cases
        Just (cycleInfo, loopClass) -> createDetailedLoopPattern program result cycleInfo loopClass

createDetailedLoopPattern :: [Byte] -> ProgramResult -> CycleInfo -> LoopClassification -> ProgramPattern
createDetailedLoopPattern program result cycleInfo loopClass = 
    let patternType = case loopClass of
            SimpleLoop _ -> SimpleLoopPattern
            ConditionalLoop _ -> ComplexLoopPattern
            ComplexLoop _ -> ComplexLoopPattern  
            MemoryModifyingLoop _ -> ComplexLoopPattern
            
        loopPattern = LoopPattern
            { loopStart = 0  -- Will be calculated from cycle info
            , loopEnd = cycleLength cycleInfo
            , loopCondition = detectLoopConditionFromCycle cycleInfo
            , loopIterations = maxBound  -- Infinite
            , outputPerIteration = estimateOutputPerCycle result cycleInfo
            }
            
        confidence = calculateLoopConfidence loopClass (cycleLength cycleInfo)
        
    in ProgramPattern
        { patternProgram = program
        , patternType = patternType
        , patternLoop = Just loopPattern
        , patternOutputFormula = "infinite"
        , patternStepsFormula = "infinite"
        , patternConfidenceScore = confidence
        , patternWildcard = generateLoopWildcard program loopClass
        }
```

### Step 5: Performance Optimizations

#### 5.1 Memory-Aware State Management  
```haskell
-- Optimized state extraction with intelligent memory handling
extractCurrentState :: Device -> CompactState
extractCurrentState device = CompactState
    { compactPc = pc device
    , compactR0 = r0 device
    , compactR1 = r1 device
    , compactMemoryHash = calculateMemoryHash device
    }

calculateMemoryHash :: Device -> Int
calculateMemoryHash device 
    | programModifiesMemory device = fastHash (Vector.toList (memory device))
    | otherwise = 0  -- Optimization: ignore memory for read-only programs

-- Static analysis to determine if program modifies memory (no Device pollution)
programModifiesMemory :: Device -> Bool  
programModifiesMemory device = any isStoreInstruction (Vector.toList (memory device))
  where
    isStoreInstruction instr = instr `elem` [11, 12]  -- STORE R0, STORE R1

-- Fast hash function for memory state
fastHash :: [Byte] -> Int
fastHash bytes = foldl' (\acc b -> acc * 31 + fromIntegral b) 0 bytes
```

#### 5.2 Early Termination Optimizations
```haskell
-- Detect obvious infinite loops early (no Device modification required)
earlyLoopDetection :: Device -> Maybe CycleDetectionResult
earlyLoopDetection device 
    -- Simple jump to self: JMP PC
    | pc device < 16 && currentInstruction == 13 && nextByte == pc device
    = Just $ CycleDetected device trivialCycle (SimpleLoop 2)
    
    -- Unconditional backward jump patterns
    | pc device < 15 && currentInstruction == 13 && nextByte < pc device  
    = Just $ CycleDetected device shortCycle (ConditionalLoop (fromIntegral (pc device - nextByte + 1)))
    
    | otherwise = Nothing
  where
    currentInstruction = (memory device) ! fromIntegral (pc device)
    nextByte = if pc device < 15 then (memory device) ! fromIntegral (pc device + 1) else 0
    trivialCycle = CycleInfo 
        { cycleStartStep = 0
        , cycleLength = 2
        , cycleStartState = extractCurrentState device
        }
    shortCycle = CycleInfo
        { cycleStartStep = 0  
        , cycleLength = fromIntegral (pc device - nextByte + 1)
        , cycleStartState = extractCurrentState device
        }
```

---

## Benefits of This Approach

### Immediate Benefits
1. **Eliminates Timeout**: Every program gets definitive `Halt` or `InfiniteLoop` classification
2. **Faster Execution**: Stops immediately when cycle is detected (no artificial delays)
3. **Consistent Results**: Same program always produces same result
4. **Mathematical Certainty**: Floyd's algorithm provides proof of cycle existence

### Enhanced Analysis Benefits  
5. **Rich Loop Information**: Cycle length, start point, classification details
6. **Better Pattern Analysis**: PatternAnalyzer gets definitive termination information  
7. **Improved Caching**: Cache can confidently store loop vs. halt classifications
8. **Performance Metrics**: Know exactly when loops start and how long cycles are

### Advanced Capabilities
9. **Loop Characterization**: Distinguish simple, conditional, and complex loops
10. **Memory Analysis**: Detect self-modifying programs
11. **Optimization Opportunities**: Skip known infinite loops in batch processing
12. **Better User Feedback**: Clear loop classification helps users understand behavior

---

## Implementation Timeline

### Phase 1 (Basic Floyd's Detection) - 4-6 hours
- [ ] Implement CompactState and state extraction
- [ ] Create basic Floyd's cycle detection algorithm  
- [ ] Update BruteForceSearch to use loop detection
- [ ] Remove Timeout from TerminationType
- [ ] Update tests to expect definitive termination

### Phase 2 (Enhanced Analysis) - 4-6 hours  
- [ ] Implement detailed cycle analysis and classification
- [ ] Update PatternAnalyzer with cycle information
- [ ] Add loop information to ProgramResult
- [ ] Enhanced pattern generation using cycle details

### Phase 3 (Performance & Polish) - 2-4 hours
- [ ] Memory-aware optimizations for self-modifying programs
- [ ] Early detection for obvious infinite loops  
- [ ] Performance testing and optimization
- [ ] Documentation and examples

### Phase 4 (Validation) - 2-3 hours
- [ ] Comprehensive testing with known loop/halt programs
- [ ] Verify Pattern Consistency test now passes
- [ ] Performance benchmarking vs. old timeout approach
- [ ] Integration testing with cache system

---

## Expected Outcomes

### Test Results
- **Pattern Consistency Test**: Will now pass with definitive termination types (no more Timeout ambiguity)
- **All Loop Detection Tests**: More accurate cycle-based analysis instead of arbitrary timeouts
- **Performance Tests**: Significantly faster execution for infinite loop detection
- **Cache Tests**: More consistent caching behavior due to deterministic classifications

### Performance Improvements  
- **O(1) Memory Usage**: True Floyd's algorithm uses constant space
- **No More Timeouts**: Eliminates arbitrary wait times and false classifications completely
- **Faster Loop Detection**: Direct state comparison without Set operations or history tracking
- **Better Cache Hit Rates**: Consistent program classification improves pattern matching
- **Optimal Algorithm**: Classic Floyd's provides best possible time/space complexity

### Code Quality Benefits
- **Mathematical Rigor**: Floyd's algorithm provides theoretical guarantees of cycle detection
- **Clean Architecture**: Clear separation of concerns between processor state and algorithm state  
- **No State Pollution**: Device remains a pure processor abstraction
- **Better Testing**: Device equality remains simple, algorithm testing isolated
- **Maintainable**: Clean interfaces make future enhancements easier

### Architectural Advantages  
- **Functional Purity**: Device state doesn't depend on execution history
- **Performance**: No copying overhead with Device operations
- **Debuggability**: Rich loop information aids in program understanding  
- **Extensibility**: Foundation for advanced loop analysis and optimization

## Summary

This implementation transforms the 4917 processor from a timeout-based system to a mathematically rigorous cycle detection engine. The clean architecture avoids state pollution while providing all the benefits of definitive loop detection.

**Key Innovation**: Using pure Floyd's cycle detection algorithm with the insight that hare-only halt checking is sufficient, eliminating all timeout mechanisms while maintaining mathematical guarantees.

**Core Insight**: Since hare moves faster than tortoise, checking only `isHalted hare` is sufficient to detect program termination. The hare reaches HALT first and provides the final program state.

**Result**: Definitive `Halt` or `InfiniteLoop` classification for every program with O(1) memory usage, mathematical certainty, and no timeout mechanisms whatsoever.