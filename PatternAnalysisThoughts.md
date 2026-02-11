# Pattern Analysis for 4917 Optimization

This document outlines pattern analysis techniques to optimize the brute force search for longest output strings in 4917 programs by identifying equivalent program classes and eliminating redundant search paths.

## Goal: WildcardPattern Module

Create a module that can analyze a `TrackedDevice` and program execution results to identify equivalent programs through:

1. **Unused Memory Wildcarding**: Mark memory locations that don't affect execution
2. **Dead Register Operation Detection**: Identify meaningless register manipulations  
3. **Register Role Equivalence**: Detect when R0/R1 can be systematically swapped
4. **Output Pattern Classification**: Group programs by output characteristics

## Implementation Using TrackedDevice Fields

The enhanced `TrackedDevice` now provides the following fields for pattern analysis:
- `accessedLocations :: Set Int` - Memory locations that were read during execution
- `r0WasConsumed :: Bool` - True if R0 was ever consumed by observable operations
- `r1WasConsumed :: Bool` - True if R1 was ever consumed by observable operations  
- `r0ContainsCombination :: Bool` - True if R0 contains result of ADD/SUB operations

## Core Principle

**Observable Equivalence**: Two programs are equivalent if they produce identical output and termination behavior, regardless of internal register/memory states that don't affect execution flow.

---

## 1. Unused Memory Location Wildcarding

### Concept
Memory locations that are never accessed during execution can be treated as wildcards since their values don't affect program behavior or output.

### Examples

**Example 1: Immediate Halt**
```
[0, 8, 15, 14] → Functionally equivalent to [0, *, *, *]
```
Program halts immediately (instruction 0), so positions 1+ are never accessed.

**Example 2: Simple Linear Execution**
```
[8, 5, 8, 12, 0] → All positions used
[8, 5, 13, 0, X] → Position 4+ unused (jumps to 0)
```

### Detection Strategy Using TrackedDevice
```haskell
-- | Identify unused memory locations that can be wildcarded
identifyUnusedMemory :: [Byte] -> TrackedDevice -> [Int]  -- Returns unused positions
identifyUnusedMemory program device = 
    let programLength = length program
        allPossibleLocations = [0..(programLength - 1)]
        accessedLocs = Set.toList (getAccessedLocations device)
    in allPossibleLocations \\ accessedLocs

-- | Create wildcard pattern from program by marking unused locations  
createMemoryWildcardPattern :: [Byte] -> TrackedDevice -> [Maybe Byte]
createMemoryWildcardPattern program device =
    let unusedPositions = Set.fromList (identifyUnusedMemory program device)
    in map (\(pos, byte) -> if pos `Set.member` unusedPositions 
                           then Nothing  -- Wildcard
                           else Just byte) (zip [0..] program)
```

**Implementation Details:**
- Use `getAccessedLocations device` to get all memory positions that were read
- Compare against program length to find positions never accessed
- Self-modifying code automatically tracked via memory read operations
- Return `Nothing` for wildcardable positions, `Just value` for required positions

---

## 2. Dead Register Operation Detection

### Instruction Classification

**Manipulating Operations** (modify register state):
- `1` (ADD), `2` (SUB), `3` (INC R0), `4` (INC R1), `5` (DEC R0), `6` (DEC R1)
- `9` (LOAD R0), `10` (LOAD R1)

**Consuming Operations** (use register values for observable effects):
- `11` (STORE R0), `12` (STORE R1) - **Memory Effect**: Register → memory
- `14` (JZ), `15` (JNZ) - **Control Flow Effect**: Register determines execution path

### Key Insight
**A manipulating operation is dead code unless there's a subsequent consuming operation that uses the modified register before it's overwritten.**

### Examples

**Example 1: Pure Dead Code**
```
[8, 15, 1, 8, 15] → Prints "15", ADD (meaningless), prints "15"
```
The ADD operation (instruction 1) is dead because R0 and R1 values are never consumed by instructions 11, 12, 14, or 15.

**Example 2: Dead Register Chains**
```
[3, 5, 0]           → INC R0, DEC R0, HALT (cancel out, meaningless)
[9, 0, 10, 1, 0]    → Load R0, Load R1, HALT (loads never used)
[3, 9, 0, 0]        → INC R0, Load R0, HALT (INC overwritten, both dead)
```

**Example 3: Meaningful Operations**
```
[3, 3, 11, 2, 0]    → INC R0 twice, STORE R0, ... (R0 consumed by STORE)
[9, 5, 14, 8, 0]    → Load R0 from [5], JZ 8 (R0 consumed by jump)
```

### Implementation Strategy Using TrackedDevice
```haskell
-- | Analyze register operations to identify dead code
analyzeRegisterOperations :: [Byte] -> TrackedDevice -> (DeadOperationAnalysis, [Int])
analyzeRegisterOperations program device = 
    let r0Used = getR0WasConsumed device
        r1Used = getR1WasConsumed device
        r0HasCombination = getR0ContainsCombination device
        
        -- Identify all register-manipulating instruction positions
        regOpPositions = findRegisterManipulatingPositions program
        
        -- Classify dead operations based on consumption flags
        deadR0Ops = if not r0Used then findR0ManipulatingPositions program else []
        deadR1Ops = if not r1Used && not r0HasCombination then findR1ManipulatingPositions program 
                   else if not r1Used && r0HasCombination then findR1OpsAfterCombination program
                   else []
        
        analysis = DeadOperationAnalysis
            { deadR0Operations = deadR0Ops
            , deadR1Operations = deadR1Ops  
            , r0ConsumptionStatus = if r0Used then "Consumed" else "Never Used"
            , r1ConsumptionStatus = if r1Used then "Consumed" 
                                   else if r0HasCombination then "Used in Combination" 
                                   else "Never Used"
            }
            
    in (analysis, deadR0Ops ++ deadR1Ops)

data DeadOperationAnalysis = DeadOperationAnalysis
    { deadR0Operations :: [Int]     -- Program positions with dead R0 operations
    , deadR1Operations :: [Int]     -- Program positions with dead R1 operations
    , r0ConsumptionStatus :: String -- Human readable status
    , r1ConsumptionStatus :: String -- Human readable status  
    } deriving (Show, Eq)

-- | Find all positions of register-manipulating instructions
findRegisterManipulatingPositions :: [Byte] -> [Int]
findRegisterManipulatingPositions program = 
    let regManipulating = [1, 2, 3, 4, 5, 6, 9, 10]  -- ADD, SUB, INC, DEC, LOAD
    in [pos | (pos, instr) <- zip [0..] program, instr `elem` regManipulating]

-- | Find R0-specific manipulating instructions  
findR0ManipulatingPositions :: [Byte] -> [Int]
findR0ManipulatingPositions program =
    let r0Manipulating = [1, 2, 3, 5, 9]  -- ADD, SUB, INC R0, DEC R0, LOAD R0
    in [pos | (pos, instr) <- zip [0..] program, instr `elem` r0Manipulating]

-- | Find R1-specific manipulating instructions
findR1ManipulatingPositions :: [Byte] -> [Int] 
findR1ManipulatingPositions program =
    let r1Manipulating = [1, 2, 4, 6, 10]  -- ADD, SUB, INC R1, DEC R1, LOAD R1
    in [pos | (pos, instr) <- zip [0..] program, instr `elem` r1Manipulating]

-- | Handle complex case: R1 operations after combination
findR1OpsAfterCombination :: [Byte] -> [Int]
findR1OpsAfterCombination program = 
    -- More sophisticated analysis needed here:
    -- Find R1 operations that occur after the combination was created
    -- but before any consumption occurs
    -- This requires execution order analysis
    []  -- Placeholder for now
```

**Implementation Details:**
- **Simple Case**: If `r0WasConsumed = False`, all R0-manipulating operations are dead
- **Simple Case**: If `r1WasConsumed = False` AND `r0ContainsCombination = False`, all R1-manipulating operations are dead  
- **Complex Case**: If `r1WasConsumed = False` but `r0ContainsCombination = True`, R1 was used indirectly
- **Combination Tracking**: The latch behavior ensures we never miss indirect R1 usage through arithmetic
- **Position Mapping**: Return actual program positions for optimization/replacement

---

## 3. Register Role Equivalence  

### Concept
Some programs produce identical output when R0/R1 roles are systematically swapped throughout the entire program.

### Swappable Operations
- `1` (ADD): R0 = R0 + R1 ↔ R1 = R1 + R0 (commutative)
- `3`↔`4` (INC R0 ↔ INC R1), `5`↔`6` (DEC R0 ↔ DEC R1)  
- `9`↔`10` (LOAD R0 ↔ LOAD R1), `11`↔`12` (STORE R0 ↔ STORE R1)

### Non-Swappable Operations
- `2` (SUB): R0 = R0 - R1 ≠ R1 = R1 - R0 (non-commutative)
- `14` (JZ), `15` (JNZ): Only test R0, not R1 (asymmetric)

### Equivalence Rules
A program is register-swappable IF:
1. Contains no SUB operations (instruction 2)
2. Contains no conditional jumps (instructions 14, 15)
3. All register operations can be meaningfully paired

### Examples
```
✓ Swappable: [3, 4, 1, 11, 5, 0]   # INC R0, INC R1, ADD, STORE R0, HALT
✓ Equivalent: [4, 3, 1, 12, 5, 0]   # INC R1, INC R0, ADD, STORE R1, HALT

✗ Non-swappable: [3, 4, 2, 0]      # Contains SUB (asymmetric)
✗ Non-swappable: [9, 0, 14, 2]     # Contains conditional jump on R0
```

---

## 4. Output Pattern Classification

### Character Count Analysis
Print operations (instruction 8) output different character counts:
- **Single Character**: Values 0-9 → e.g., `8, 5` outputs "5"
- **Double Character**: Values 10-15 → e.g., `8, 12` outputs "12"

### Pattern Categories
- **Fixed Output**: Only immediate print values → deterministic length
- **Computed Output**: Print register/memory values → variable length  
- **Hybrid**: Mix of immediate and computed prints

### Examples
```
[8, 5, 8, 12, 0]     # Fixed: "512" (3 chars)
[3, 3, 8, R0, 0]     # Computed: depends on final R0 value
[8, 5, 9, 0, 8, R0]  # Hybrid: "5" + computed R0 value
```

---

## 5. Additional Equivalence Opportunities

### Loop Pattern Recognition
- **Infinite Loops**: Programs that never halt can be detected and filtered
- **Finite Loops**: Loops with identical output patterns can be grouped
- **Loop Unrolling**: Some loops may be equivalent to linear sequences

### Self-Modification Detection
- Programs that modify their own code during execution
- Detect when stores affect currently executing or future code locations
- Group programs with equivalent post-modification states

### Jump Target Optimization
- **Unreachable Code**: Code sections never reached by any execution path
- **Jump Consolidation**: Multiple jumps to same effective location

---

## Implementation Plan

### Phase 1: Core Infrastructure
1. **TrackedDevice Analysis**: Extract memory access patterns and register usage
2. **Unused Memory Detection**: Mark wildcardable memory locations
3. **Dead Register Detection**: Identify meaningless register operations

### Phase 2: Equivalence Detection  
4. **Register Role Swapping**: Detect and group swappable programs
5. **Output Pattern Analysis**: Classify programs by output characteristics

### Phase 3: Advanced Optimizations
6. **Loop Pattern Recognition**: Detect and optimize loop structures
7. **Self-Modification Handling**: Handle dynamic code modification cases

## Practical Implementation Examples

### Example 1: Complete Analysis Workflow
```haskell
-- | Complete pattern analysis using TrackedDevice
analyzeProgram :: [Byte] -> IO (ProgramAnalysis)
analyzeProgram program = do
    case createTrackedDevice program of
        Left err -> return $ ProgramAnalysis program [] [] "Error: " ++ show err
        Right device -> do
            let finalDevice = runTrackedProgram device 1000
            
            -- 1. Unused Memory Analysis  
            let unusedMemory = identifyUnusedMemory program finalDevice
                memoryPattern = createMemoryWildcardPattern program finalDevice
            
            -- 2. Dead Register Analysis
            let (regAnalysis, deadPositions) = analyzeRegisterOperations program finalDevice
            
            return $ ProgramAnalysis
                { originalProgram = program
                , unusedMemoryPositions = unusedMemory  
                , deadRegisterPositions = deadPositions
                , analysisReport = formatAnalysisReport memoryPattern regAnalysis
                }

data ProgramAnalysis = ProgramAnalysis
    { originalProgram :: [Byte]
    , unusedMemoryPositions :: [Int]
    , deadRegisterPositions :: [Int]  
    , analysisReport :: String
    } deriving (Show)
```

### Example 2: Real Program Analysis Results
```haskell
-- Program: [8, 5, 3, 4, 1, 11, 0, 0] 
-- PRINT 5, INC R0, INC R1, ADD, STORE R0, HALT

Expected Results:
- accessedLocations: {0, 1, 2, 3, 4, 5, 6}  -- All instructions + operands executed
- r0WasConsumed: True     -- R0 consumed by STORE R0  
- r1WasConsumed: True     -- R1 consumed via ADD combination
- r0ContainsCombination: True  -- ADD sets this flag
- unusedMemoryPositions: [7]   -- Position 7 never accessed
- deadRegisterPositions: []    -- No dead operations (all registers used)

-- Program: [8, 5, 3, 4, 0]
-- PRINT 5, INC R0, INC R1, HALT  

Expected Results:
- accessedLocations: {0, 1, 2, 3, 4}  -- All instructions executed
- r0WasConsumed: False    -- R0 never consumed
- r1WasConsumed: False    -- R1 never consumed  
- r0ContainsCombination: False  -- No combination operations
- unusedMemoryPositions: []     -- All positions accessed
- deadRegisterPositions: [2, 3]  -- Both INC operations are dead

-- Program: [8, 5, 3, 4, 1, 5, 0, X, X, ...]  
-- PRINT 5, INC R0, INC R1, ADD, DEC R0, HALT

Expected Results:
- accessedLocations: {0, 1, 2, 3, 4, 5, 6}  -- Instructions 0-6 executed
- r0WasConsumed: False    -- R0 never consumed by STORE/JZ/JNZ
- r1WasConsumed: False    -- R1 never consumed directly or via combination  
- r0ContainsCombination: True  -- ADD sets this flag (latch behavior)
- unusedMemoryPositions: [7, 8, 9, ...]  -- Positions 7+ never accessed
- deadRegisterPositions: [2, 3, 4, 5]     -- All register ops are dead
```

## WildcardPattern Design: Enhanced OptimizedInstruction Types

### Core Pattern Types
```haskell
data OptimizedInstruction = 
    Required Byte           -- Must be exactly this byte value
  | Wildcard                -- Can be any value (0-15)
  | AnyOf [Byte]           -- Can be any value from this specific list
  deriving (Show, Eq)

data OptimizedProgram = OptimizedProgram
    { originalProgram :: [Byte]
    , wildcardPattern :: [OptimizedInstruction]
    , reductionFactor :: Double  -- How much search space was reduced
    , equivalenceClass :: String -- Canonical representation for grouping
    } deriving (Show)
```

### Pattern Classification Strategy
```haskell
-- | Create optimized pattern based on analysis results
optimizeProgram :: ProgramAnalysis -> OptimizedProgram
optimizeProgram analysis = 
    let program = originalProgram analysis
        unused = Set.fromList (unusedMemoryPositions analysis)  
        dead = Set.fromList (deadRegisterPositions analysis)
        
        -- Create sophisticated pattern  
        wildcardPattern = map (classifyPosition analysis) (zip [0..] program)
            
    in OptimizedProgram
        { originalProgram = program
        , wildcardPattern = wildcardPattern  
        , reductionFactor = calculateReductionFactor wildcardPattern
        , equivalenceClass = generateEquivalenceClass wildcardPattern
        }

-- | Classify each program position based on analysis
classifyPosition :: ProgramAnalysis -> (Int, Byte) -> OptimizedInstruction
classifyPosition analysis (pos, originalByte) 
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos `elem` deadRegisterPositions analysis = classifyDeadRegisterPosition originalByte
    | otherwise = Required originalByte

-- | Handle dead register positions with instruction grouping  
classifyDeadRegisterPosition :: Byte -> OptimizedInstruction
classifyDeadRegisterPosition originalByte 
    | originalByte `elem` registerManipulating = AnyOf deadCodeEquivalentInstructions
    | otherwise = Required originalByte  -- Non-register instructions must stay as-is
```

### Advanced Pattern Applications

#### 1. Instruction Category Constants
```haskell
-- Core instruction categories based on observable effects
registerManipulating :: [Byte]
registerManipulating = [1, 2, 3, 4, 5, 6, 9, 10]
-- Instructions that modify register values but have no direct observable effect
-- 1=ADD, 2=SUB, 3=INC_R0, 4=INC_R1, 5=DEC_R0, 6=DEC_R1, 9=LOAD_R0, 10=LOAD_R1

registerConsuming :: [Byte] 
registerConsuming = [11, 12, 14, 15]
-- Instructions that use register values for observable effects (memory/control flow)
-- 11=STORE_R0, 12=STORE_R1, 14=JZ, 15=JNZ

nonRegisterInstructions :: [Byte]
nonRegisterInstructions = [0, 7, 8, 13]
-- Instructions that don't involve registers at all
-- 0=HALT, 7=NOP, 8=PRINT, 13=JMP

-- Register-specific operation categories
r0ManipulatingOnly :: [Byte]  
r0ManipulatingOnly = [3, 5, 9]
-- Instructions that only manipulate R0: INC_R0, DEC_R0, LOAD_R0

r1ManipulatingOnly :: [Byte]
r1ManipulatingOnly = [4, 6, 10] 
-- Instructions that only manipulate R1: INC_R1, DEC_R1, LOAD_R1

bothRegisterOperations :: [Byte]
bothRegisterOperations = [1, 2]
-- Instructions that manipulate both registers: ADD, SUB

r0ConsumingOnly :: [Byte]
r0ConsumingOnly = [11, 14, 15]
-- Instructions that only consume R0: STORE_R0, JZ, JNZ

r1ConsumingOnly :: [Byte] 
r1ConsumingOnly = [12]
-- Instructions that only consume R1: STORE_R1

-- Derived categories for common use cases
deadCodeEquivalentInstructions :: [Byte]
deadCodeEquivalentInstructions = registerManipulating
-- When registers are never consumed, all register-manipulating instructions are equivalent

r0DeadCodeEquivalent :: [Byte]
r0DeadCodeEquivalent = r0ManipulatingOnly ++ bothRegisterOperations  -- [3, 5, 9, 1, 2]
-- When R0 is never consumed, these operations are equivalent

r1DeadCodeEquivalent :: [Byte] 
r1DeadCodeEquivalent = r1ManipulatingOnly ++ bothRegisterOperations  -- [4, 6, 10, 1, 2]
-- When R1 is never consumed, these operations are equivalent

-- | Create more sophisticated patterns based on register usage
createAdvancedPattern :: ProgramAnalysis -> [OptimizedInstruction]
createAdvancedPattern analysis = 
    map (classifyAdvancedPosition analysis) (zip [0..] (originalProgram analysis))

classifyAdvancedPosition :: ProgramAnalysis -> (Int, Byte) -> OptimizedInstruction  
classifyAdvancedPosition analysis (pos, byte)
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos `elem` deadRegisterPositions analysis && byte `elem` registerManipulating = 
        AnyOf deadCodeEquivalentInstructions  -- Any register manipulation is equivalent when dead
    | otherwise = Required byte
```

#### 2. Search Space Reduction Calculation
```haskell
-- | Calculate search space reduction factor
calculateReductionFactor :: [OptimizedInstruction] -> Double
calculateReductionFactor pattern = 
    let totalOriginalSpace = 16 ^ length pattern  -- 16^n for original program
        reducedSpace = product (map instructionSpaceSize pattern)
        reductionFactor = fromIntegral totalOriginalSpace / fromIntegral reducedSpace
    in reductionFactor

instructionSpaceSize :: OptimizedInstruction -> Int
instructionSpaceSize instruction = case instruction of
    Required _ -> 1      -- Only one valid value
    Wildcard -> 16       -- All 16 values valid  
    AnyOf options -> length options  -- Number of valid options

-- Example calculations:
-- Original: [8, 5, 3, 4, 0] = 16^5 = 1,048,576 possibilities
-- Optimized: [Required 8, Required 5, AnyOf [1,2,3,4,5,6,9,10], AnyOf [1,2,3,4,5,6,9,10], Required 0]
-- Reduced: 1 × 1 × 8 × 8 × 1 = 64 possibilities  
-- Reduction Factor: 1,048,576 / 64 = 16,384× reduction!
```

### Practical Pattern Examples

#### Example 1: Complete Dead Register Analysis
```haskell
-- Original: [8, 5, 3, 4, 0] -- PRINT 5, INC R0, INC R1, HALT
-- Analysis: R0 and R1 never consumed, positions 2,3 are dead register operations
-- Pattern: [Required 8, Required 5, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, Required 0]
-- Reduction: 16^5 → 1×1×8×8×1 = 64 vs original 1,048,576 = 16,384× reduction
```

#### Example 2: Mixed Memory and Register Optimization  
```haskell
-- Original: [8, 5, 3, 4, 0, X, X, X] (length 5, positions 5+ unused)
-- Analysis: positions 2,3 are dead register ops, positions 5+ unused  
-- Pattern: [Required 8, Required 5, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, Required 0, Wildcard, Wildcard, Wildcard]
-- Reduction: 16^8 → 1×1×8×8×1×16×16×16 = 262,144 vs original 4.3B = 16,384× reduction
```

#### Example 3: Partial Register Consumption
```haskell
-- Original: [3, 4, 1, 11, 0] -- INC R0, INC R1, ADD, STORE R0, HALT
-- Analysis: R0 consumed (via STORE), R1 consumed (via ADD combination), all operations meaningful
-- Pattern: [Required 3, Required 4, Required 1, Required 11, Required 0]
-- Reduction: 16^5 → 1×1×1×1×1 = No reduction (optimal program)
```

#### Example 4: Selective Register Dead Code
```haskell
-- Scenario: R0 never consumed, but R1 is consumed
-- R0-only operations can use: AnyOf r0DeadCodeEquivalent  -- [3, 5, 9, 1, 2]  
-- R1-only operations must stay: Required (because R1 is meaningful)
-- Both-register operations (ADD/SUB): Depends on analysis context

-- Example program: [3, 4, 12, 1, 0] -- INC R0, INC R1, STORE R1, HALT  
-- Analysis: R0 never consumed, R1 consumed by STORE R1
-- Pattern: [AnyOf r0DeadCodeEquivalent, Required 4, Required 12, Required 1, Required 0]
-- The INC R0 can become any R0-manipulating instruction since R0 is never used
```

#### Example 5: Advanced Instruction Category Usage
```haskell
-- Using specific instruction categories for targeted optimization:

-- When only memory operations matter:
nonMemoryInstructions = nonRegisterInstructions ++ registerManipulating
-- [0, 7, 8, 13] ++ [1, 2, 3, 4, 5, 6, 9, 10] = all non-memory-affecting instructions

-- When only control flow matters:
controlFlowInstructions = [0, 13, 14, 15]  -- HALT, JMP, JZ, JNZ

-- When register modifications don't matter but consumption does:
meaningfulInstructions = nonRegisterInstructions ++ registerConsuming
-- [0, 7, 8, 13] ++ [11, 12, 14, 15] = instructions that have direct observable effects
```
```

### Testing Strategy
- **Exhaustive Verification**: Test on small program lengths (3-4) where full enumeration is feasible
- **Spot Checking**: Random sampling to verify equivalence claims
- **Performance Benchmarks**: Ensure optimizations provide measurable speedup