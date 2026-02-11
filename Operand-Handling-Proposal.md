# Proposal: Proper Operand Handling in WildcardPattern Generation

## Problem Statement

Currently, the `optimizeProgram` function incorrectly treats operand positions as potential dead register operations. For example:

```haskell
-- Program: [8, 5, 3, 4, 0] -- PRINT 5, INC R0, INC R1, HALT  
-- Current incorrect pattern: [Required 8, AnyOf deadCodeEquivalentInstructions, ...]
-- Should be: [Required 8, Required 5, AnyOf deadCodeEquivalentInstructions, ...]
```

Position 1 contains the operand `5` for the PRINT instruction, not an instruction itself, so it must be exactly `Required 5`.

## Core Issue

The `classifyMemoryPosition` function doesn't distinguish between:
1. **Instruction positions** - Can potentially be optimized (if dead register ops)
2. **Operand positions** - Must always be `Required` (exact values needed for instruction execution)

## Proposed Solutions

### Option 1: Instruction-Aware Position Classification

**Approach**: Track which positions are operands during program analysis.

```haskell
data PositionType = InstructionPosition | OperandPosition deriving (Show, Eq)

data EnhancedProgramAnalysis = EnhancedProgramAnalysis
    { programOriginal :: [Byte]
    , positionTypes :: [PositionType]  -- NEW: Track instruction vs operand positions
    , unusedMemoryPositions :: [Int]
    , deadRegisterPositions :: [Int]  
    , registerAnalysis :: DeadOperationAnalysis
    , trackedDevice :: TrackedDevice
    } deriving (Show)

-- Enhanced classification that respects operand positions
classifyMemoryPositionEnhanced :: EnhancedProgramAnalysis -> Int -> OptimizedInstruction  
classifyMemoryPositionEnhanced analysis pos 
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos < length (positionTypes analysis) && (positionTypes analysis !! pos) == OperandPosition = 
        Required ((programOriginal analysis) !! pos)  -- Operands are always Required
    | pos `elem` deadRegisterPositions analysis = 
        classifyDeadRegisterPosition ((programOriginal analysis) !! pos)
    | pos < length (programOriginal analysis) = 
        Required ((programOriginal analysis) !! pos)
    | otherwise = Wildcard
```

**Pros:**
- Accurate operand detection
- Clean separation of instruction vs operand logic
- Extensible for future instruction analysis

**Cons:**
- Requires program parsing to identify instruction/operand boundaries
- More complex analysis phase

### Option 2: Instruction-Length-Based Analysis

**Approach**: Use instruction opcodes to determine operand positions dynamically.

```haskell
-- | Determine if an instruction has an operand
instructionHasOperand :: Byte -> Bool
instructionHasOperand instr = instr `elem` [8, 9, 10, 11, 12, 13, 14, 15]  -- Two-byte instructions

-- | Generate list of operand positions in a program
identifyOperandPositions :: [Byte] -> [Int]
identifyOperandPositions program = go 0 program []
  where
    go pos [] acc = reverse acc
    go pos (instr:rest) acc
        | pos >= length program = reverse acc
        | instructionHasOperand instr = 
            if pos + 1 < length program 
            then go (pos + 2) (drop 1 rest) ((pos + 1) : acc)  -- Add operand position
            else reverse acc
        | otherwise = go (pos + 1) rest acc

-- Modified classification
classifyMemoryPositionWithOperands :: ProgramAnalysis -> Int -> OptimizedInstruction  
classifyMemoryPositionWithOperands analysis pos 
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos `elem` identifyOperandPositions (programOriginal analysis) = 
        Required ((programOriginal analysis) !! pos)  -- Operands always Required
    | pos `elem` deadRegisterPositions analysis = 
        classifyDeadRegisterPosition ((programOriginal analysis) !! pos)
    | pos < length (programOriginal analysis) = 
        Required ((programOriginal analysis) !! pos)
    | otherwise = Wildcard
```

**Pros:**
- No changes to ProgramAnalysis data structure
- Dynamic operand detection based on instruction set
- Leverages existing 4917 instruction knowledge

**Cons:**
- Repeated parsing during optimization
- Tightly coupled to instruction set details

### Option 3: Pre-computed Operand Map

**Approach**: Parse program once during analysis to create operand position map.

```haskell
-- | Parse program to identify instruction and operand positions
parseInstructionPositions :: [Byte] -> (Set Int, Set Int)  -- (instructionPositions, operandPositions)
parseInstructionPositions program = go 0 program Set.empty Set.empty
  where
    go pos [] instrSet operandSet = (instrSet, operandSet)
    go pos (instr:rest) instrSet operandSet
        | pos >= length program = (instrSet, operandSet)
        | instructionHasOperand instr = 
            let newInstrSet = Set.insert pos instrSet
                newOperandSet = if pos + 1 < length program 
                               then Set.insert (pos + 1) operandSet
                               else operandSet
            in go (pos + 2) (drop 1 rest) newInstrSet newOperandSet
        | otherwise = 
            go (pos + 1) rest (Set.insert pos instrSet) operandSet

-- Add to existing ProgramAnalysis
data ProgramAnalysis = ProgramAnalysis
    { programOriginal :: [Byte]
    , unusedMemoryPositions :: [Int]
    , deadRegisterPositions :: [Int]  
    , registerAnalysis :: DeadOperationAnalysis
    , trackedDevice :: TrackedDevice
    , operandPositions :: Set Int  -- NEW: Pre-computed operand positions
    } deriving (Show)

-- Simplified classification
classifyMemoryPositionWithMap :: ProgramAnalysis -> Int -> OptimizedInstruction  
classifyMemoryPositionWithMap analysis pos 
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos `Set.member` operandPositions analysis = 
        Required ((programOriginal analysis) !! pos)  -- Operands always Required
    | pos `elem` deadRegisterPositions analysis = 
        classifyDeadRegisterPosition ((programOriginal analysis) !! pos)
    | pos < length (programOriginal analysis) = 
        Required ((programOriginal analysis) !! pos)
    | otherwise = Wildcard
```

**Pros:**
- Single parse during analysis phase
- Fast lookup during optimization
- Clean separation of concerns

**Cons:**
- Slight increase in ProgramAnalysis complexity
- Pre-computed data that could get out of sync

### Option 4: Instruction Set Constant Approach

**Approach**: Define instruction set constants and use them for operand detection.

```haskell
-- Define instruction categories more precisely
singleByteInstructions :: [Byte]
singleByteInstructions = [0, 1, 2, 3, 4, 5, 6, 7]

twoByteInstructions :: [Byte] 
twoByteInstructions = [8, 9, 10, 11, 12, 13, 14, 15]

-- | Check if position is an operand based on instruction set knowledge
isOperandPosition :: [Byte] -> Int -> Bool
isOperandPosition program pos 
    | pos <= 0 = False
    | pos >= length program = False
    | otherwise = 
        let prevPos = pos - 1
            prevInstr = program !! prevPos
        in prevInstr `elem` twoByteInstructions

-- Simple classification with operand detection
classifyMemoryPositionInstructionSet :: ProgramAnalysis -> Int -> OptimizedInstruction  
classifyMemoryPositionInstructionSet analysis pos 
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | isOperandPosition (programOriginal analysis) pos = 
        Required ((programOriginal analysis) !! pos)  -- Operands always Required
    | pos `elem` deadRegisterPositions analysis = 
        classifyDeadRegisterPosition ((programOriginal analysis) !! pos)
    | pos < length (programOriginal analysis) = 
        Required ((programOriginal analysis) !! pos)
    | otherwise = Wildcard
```

**Pros:**
- Minimal code changes
- Leverages instruction set constants
- Simple and direct approach

**Cons:**
- Assumes well-formed programs
- Limited error handling for malformed instruction sequences

## Comparison Matrix

| Option | Code Complexity | Performance | Accuracy | Maintainability | Implementation Effort |
|--------|----------------|-------------|----------|-----------------|----------------------|
| 1. Enhanced Analysis | High | Good | Excellent | Good | High |
| 2. Dynamic Parsing | Medium | Fair | Good | Fair | Medium |
| 3. Pre-computed Map | Medium | Excellent | Excellent | Good | Medium |
| 4. Instruction Set | Low | Excellent | Good | Excellent | Low |

## Recommended Approach

**Option 3: Pre-computed Operand Map** is the recommended solution because:

1. **Performance**: Single parse, fast lookups during optimization
2. **Accuracy**: Correctly identifies all operand positions
3. **Clean Design**: Clear separation between analysis and optimization phases
4. **Maintainability**: Easy to understand and extend

## Implementation Plan

### Phase 1: Update ProgramAnalysis
- Add `operandPositions :: Set Int` field
- Add `parseInstructionPositions` function
- Update `analyzeProgram` to compute operand positions

### Phase 2: Update Classification  
- Modify `classifyMemoryPosition` to check operand positions first
- Ensure operands are always `Required`

### Phase 3: Update Tests
- Fix test expectations for operand positions
- Add specific tests for instruction/operand boundary detection
- Validate complex programs with multiple two-byte instructions

## Example Results

```haskell
-- Program: [8, 5, 3, 4, 0] -- PRINT 5, INC R0, INC R1, HALT
-- Before: [Required 8, AnyOf dead, AnyOf dead, AnyOf dead, Required 0, Wildcard×11]  
-- After:  [Required 8, Required 5, AnyOf dead, AnyOf dead, Required 0, Wildcard×11]

-- Program: [9, 12, 11, 5, 0] -- LOAD R0 from 12, STORE R0 to 5, HALT
-- Before: [AnyOf dead, AnyOf dead, Required 11, Required 5, Required 0, Wildcard×11]
// After:  [Required 9, Required 12, Required 11, Required 5, Required 0, Wildcard×11]
```

This ensures that operand values are preserved exactly as required for correct program execution while still enabling optimization of dead register operations.