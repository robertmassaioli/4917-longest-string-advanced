# Usage-Aware Optimization Display Proposal

## Overview

This proposal enhances the `prettyPrintOptimizedProgram` output to accurately reflect how each memory position was actually used during program execution, rather than making assumptions about instruction interpretations.

## Problem Statement

Currently, the optimization display shows misleading information like:
```
║  0: Required    LOAD_R0 (9)                                                          ║
║ 15: Required    INC_R0 (3)                                                           ║
```

This incorrectly assumes that:
- Position 0 will always execute as a `LOAD_R0` instruction
- Position 15 will always execute as an `INC_R0` instruction

In reality, these positions contain **values** (9 and 3) that could be used as instructions, operands, or both depending on program flow.

## Proposed Solution

### Enhanced Display Format

Replace assumption-based descriptions with actual usage information from `TrackedProcessor` analysis:

```
╔══════════════════════════════════════════════════════════════════════════════════════╗
║                                 OPTIMIZED PROGRAM                                     ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║ Original Program: [9,15,14,8,8,5,13,10,8,7,0,0,0,0,0,3]                              ║
║ Equivalence Class: 9151488[0123456789]1310**0****3                                   ║
║ Reduction Factor: 109951162777.60x                                                           ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║                              WILDCARD PATTERN (16-byte)                              ║
╠══════════════════════════════════════════════════════════════════════════════════════╣
║  0: Required    9          [Used as: Instruction (LOAD R0)]                    ║
║  1: Required    15         [Used as: Operand for LOAD R0]                      ║
║  2: Required    14         [Used as: Instruction (JZ)]                         ║
║  3: Required    8          [Used as: Operand for JZ]                           ║
║  4: Required    8          [Used as: Instruction (PRINT)]                      ║
║  5: AnyOf       [0-9]      [Used as: Operand for PRINT]                       ║
║  6: Required    13         [Used as: Instruction (JMP)]                        ║
║  7: Required    10         [Used as: Operand for JMP]                          ║
║  8: Wildcard    *          [Used as: Instruction (PRINT)]                      ║
║  9: Wildcard    *          [Used as: Operand for PRINT]                        ║
║ 10: Required    0          [Used as: Instruction (HALT)]                       ║
║ 11: Wildcard    *          [Used as: Never accessed]                           ║
║ 12: Wildcard    *          [Used as: Never accessed]                           ║
║ 13: Wildcard    *          [Used as: Never accessed]                           ║
║ 14: Wildcard    *          [Used as: Never accessed]                           ║
║ 15: Required    3          [Used as: Operand for LOAD R0]                      ║
╚══════════════════════════════════════════════════════════════════════════════════════╝
```

### Mixed Usage Example

For memory positions used in multiple ways:

```
║  4: Required    8          [Used as: Instruction (PRINT) + Operand for JMP]    ║
║  7: AnyOf       [10-15]    [Used as: Instruction (LOAD R1) + Operand for JZ]   ║
```

## Data Flow Architecture

### 1. Enhanced TrackedProcessor Analysis

Extend `TrackedProcessor` to capture **detailed usage information** during execution:

```haskell
-- New data structure for memory position usage
data MemoryUsage = MemoryUsage
    { position :: Int
    , usageTypes :: [UsageType]
    , contextInfo :: [UsageContext]
    } deriving (Show, Eq)

data UsageType 
    = UsedAsInstruction InstructionName
    | UsedAsOperand InstructionName Int  -- instruction name + operand index
    | NeverAccessed
    deriving (Show, Eq)

data UsageContext = UsageContext
    { pc :: Word4           -- Program counter when accessed
    , step :: Int           -- Execution step number
    , accessType :: AccessType
    } deriving (Show, Eq)

data AccessType 
    = InstructionFetch
    | OperandRead Int       -- operand index (0 for single operand, 0-1 for two-operand)
    deriving (Show, Eq)

-- Enhanced TrackedDevice
data TrackedDevice = TrackedDevice
    { device :: Device
    , accessedLocations :: Set Int
    , instructionLocations :: Set Int
    , operandLocations :: Set Int
    , mixedUsageLocations :: Set Int
    , detailedUsage :: Map Int MemoryUsage  -- NEW: detailed usage tracking
    -- ... existing fields
    } deriving (Show)
```

### 2. Enhanced Execution Tracking

Modify `stepTrackedProgram` to capture detailed usage:

```haskell
stepTrackedProgram :: TrackedDevice -> TrackedDevice
stepTrackedProgram trackedDevice@TrackedDevice{..} =
    let currentPC = fromIntegral (pc device)
        instruction = (memory device) Vector.! currentPC
        
        -- Record instruction fetch
        instructionUsage = recordUsage currentPC (UsedAsInstruction (instructionName instruction))
        
        -- Record operand accesses based on instruction type
        operandUsages = recordOperandUsages instruction currentPC
        
        -- Execute the instruction
        (newDevice, outputInfo, finished) = stepProgram device
        
        -- Update tracking with detailed usage
        newTrackedDevice = trackedDevice 
            { device = newDevice
            , detailedUsage = updateDetailedUsage (detailedUsage trackedDevice) 
                                (instructionUsage : operandUsages)
            , -- ... update other tracking fields
            }
    in newTrackedDevice

-- Helper to record operand usage
recordOperandUsages :: Word4 -> Int -> [UsageUpdate]
recordOperandUsages instruction pc
    | instruction >= 8 && instruction <= 15 = 
        -- Two-byte instruction: next position is operand
        [recordUsage (pc + 1) (UsedAsOperand (instructionName instruction) 0)]
    | otherwise = []

-- Helper to determine instruction name
instructionName :: Word4 -> InstructionName
instructionName 0 = "HALT"
instructionName 1 = "ADD"
instructionName 2 = "SUB"
instructionName 3 = "INC R0"
instructionName 4 = "INC R1"
instructionName 5 = "DEC R0"
instructionName 6 = "DEC R1"
instructionName 7 = "NOP"
instructionName 8 = "PRINT"
instructionName 9 = "LOAD R0"
instructionName 10 = "LOAD R1"
instructionName 11 = "STORE R0"
instructionName 12 = "STORE R1"
instructionName 13 = "JMP"
instructionName 14 = "JZ"
instructionName 15 = "JNZ"
```

### 3. Enhanced ProgramAnalysis

Extend `ProgramAnalysis` to include detailed usage information:

```haskell
data ProgramAnalysis = ProgramAnalysis
    { originalProgram :: [Byte]
    , trackedDevice :: TrackedDevice
    , registerAnalysis :: DeadOperationAnalysis
    , memoryAnalysis :: EnhancedMemoryAnalysis
    , detailedUsageMap :: Map Int MemoryUsage  -- NEW: from TrackedDevice
    , unusedMemoryPositions :: [Int]
    } deriving (Show)

-- Update analyzeProgram to carry through detailed usage
analyzeProgram :: [Byte] -> TrackedDevice -> ProgramAnalysis
analyzeProgram program finalDevice = 
    ProgramAnalysis
        { originalProgram = program
        , trackedDevice = finalDevice
        , registerAnalysis = analyzeDeadOperations finalDevice
        , memoryAnalysis = analyzeEnhancedMemory finalDevice
        , detailedUsageMap = detailedUsage finalDevice  -- NEW
        , unusedMemoryPositions = findUnusedPositions finalDevice
        }
```

### 4. Enhanced OptimizedProgram Display

Update `prettyPrintOptimizedProgram` to use detailed usage information:

```haskell
-- Enhanced pretty printing with usage information
prettyPrintOptimizedProgram :: OptimizedProgram -> String
prettyPrintOptimizedProgram opt = 
    let analysis = programAnalysis opt
        usageMap = detailedUsageMap analysis
        pattern = wildcardPattern opt
    in unlines $ 
        [ topBorder
        , headerSection opt
        , patternSection pattern usageMap
        , bottomBorder
        ]

-- Format individual pattern line with usage info
formatPatternLine :: Int -> OptimizedInstruction -> Map Int MemoryUsage -> String
formatPatternLine pos instr usageMap = 
    let posStr = printf "%2d:" pos
        instrStr = formatOptimizedInstruction instr
        usageStr = formatUsageInfo (Map.lookup pos usageMap)
    in printf "║ %s %-12s %-30s ║" posStr instrStr usageStr

-- Format usage information
formatUsageInfo :: Maybe MemoryUsage -> String
formatUsageInfo Nothing = "[Used as: Unknown]"
formatUsageInfo (Just usage) = 
    "[Used as: " ++ formatUsageTypes (usageTypes usage) ++ "]"

formatUsageTypes :: [UsageType] -> String
formatUsageTypes [] = "Never accessed"
formatUsageTypes [UsedAsInstruction name] = "Instruction (" ++ name ++ ")"
formatUsageTypes [UsedAsOperand instrName _] = "Operand for " ++ instrName
formatUsageTypes [NeverAccessed] = "Never accessed"
formatUsageTypes multiple = intercalate " + " (map formatSingleUsage multiple)
  where
    formatSingleUsage (UsedAsInstruction name) = "Instruction (" ++ name ++ ")"
    formatSingleUsage (UsedAsOperand instrName _) = "Operand for " ++ instrName
    formatSingleUsage NeverAccessed = "Never accessed"
```

## Mixed Usage Implementation

### Example Scenario

Consider a program where position 4 is accessed both ways:

```haskell
program = [13, 4, 7, 0, 8, 5, 0, 0]  
-- JMP 4, NOP, HALT, PRINT 5, HALT, padding
```

During execution:
1. **Step 1**: PC=0, instruction `13` (JMP), operand at position 1 is `4`
2. **Step 2**: PC=4, instruction `8` (PRINT), operand at position 5 is `5`

Position 4 usage:
- **As operand**: Used by JMP instruction at step 1
- **As instruction**: Executed as PRINT instruction at step 2

### Data Structure Updates

```haskell
-- Position 4 would have:
MemoryUsage 
    { position = 4
    , usageTypes = 
        [ UsedAsOperand "JMP" 0        -- Used as operand for JMP
        , UsedAsInstruction "PRINT"    -- Used as PRINT instruction
        ]
    , contextInfo = 
        [ UsageContext { pc = 0, step = 1, accessType = OperandRead 0 }
        , UsageContext { pc = 4, step = 2, accessType = InstructionFetch }
        ]
    }
```

### Display Output

```
║  4: Required    8          [Used as: Operand for JMP + Instruction (PRINT)]    ║
```

## Implementation Plan

### Phase 1: Data Structure Extensions
1. Add `MemoryUsage`, `UsageType`, `UsageContext` data types
2. Extend `TrackedDevice` with `detailedUsage` field
3. Extend `ProgramAnalysis` with `detailedUsageMap` field

### Phase 2: Execution Tracking Enhancement
1. Modify `stepTrackedProgram` to record detailed usage
2. Add helper functions for usage recording
3. Implement instruction name mapping

### Phase 3: Display Enhancement
1. Update `prettyPrintOptimizedProgram` to use usage information
2. Implement usage formatting functions
3. Handle mixed usage cases

### Phase 4: Testing and Validation
1. Test with single-usage examples
2. Test with mixed-usage examples
3. Verify all 16 instruction types are handled correctly
4. Test with complex control flow programs

## Benefits

### Accuracy
- **No more misleading instruction assumptions**
- Shows exactly how each position was used during execution
- Accurate representation of program behavior

### Educational Value
- **Helps users understand instruction vs operand roles**
- Shows the dynamic nature of memory usage
- Illustrates how PC movement affects memory interpretation

### Debugging Support
- **Detailed execution context for each memory access**
- Step-by-step usage information
- Clear visualization of memory access patterns

### Optimization Insight
- **Shows why certain positions must be Required vs Wildcard**
- Explains the relationship between usage patterns and optimization opportunities
- Demonstrates the impact of control flow on memory access

## Example Outputs

### Simple Linear Program
```
Program: [8, 5, 0]

║  0: Required    8          [Used as: Instruction (PRINT)]                      ║
║  1: Required    5          [Used as: Operand for PRINT]                       ║
║  2: Required    0          [Used as: Instruction (HALT)]                      ║
║  3: Wildcard    *          [Used as: Never accessed]                          ║
```

### Complex Control Flow with Mixed Usage
```
Program: [13, 4, 7, 0, 8, 5, 0]

║  0: Required    13         [Used as: Instruction (JMP)]                       ║
║  1: Required    4          [Used as: Operand for JMP]                         ║
║  2: Wildcard    *          [Used as: Never accessed]                          ║
║  3: Wildcard    *          [Used as: Never accessed]                          ║
║  4: Required    8          [Used as: Instruction (PRINT)]                     ║
║  5: Required    5          [Used as: Operand for PRINT]                       ║
║  6: Required    0          [Used as: Instruction (HALT)]                      ║
```

### Self-Modifying Program (Advanced)
```
Program: [11, 3, 8, 0, 5]  -- STORE R0 [3], PRINT 5, padding

║  0: Required    11         [Used as: Instruction (STORE R0)]                  ║
║  1: Required    3          [Used as: Operand for STORE R0]                    ║
║  2: Required    8          [Used as: Instruction (PRINT)]                     ║
║  3: AnyOf       [0-15]     [Used as: Operand for PRINT + Store target]       ║
║  4: Wildcard    *          [Used as: Never accessed]                          ║
```

## Backward Compatibility

This enhancement is **fully backward compatible**:
- Existing `OptimizedProgram` structure unchanged
- New usage information is additive
- Fallback to current display if usage data unavailable
- All existing optimization logic preserved

## Conclusion

This proposal transforms the optimization display from making incorrect assumptions to providing accurate, detailed information about how each memory position was actually used during program execution. It enhances both the educational value and debugging capabilities while maintaining full backward compatibility with existing optimization logic.

The implementation provides a solid foundation for understanding program behavior and optimization opportunities in the 4917 processor environment.