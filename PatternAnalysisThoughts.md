# Pattern Analysis for 4917 Optimization

This document outlines pattern analysis techniques to optimize the brute force search for longest output strings in 4917 programs by identifying equivalent program classes and eliminating redundant search paths.

## Goal: WildcardPattern Module

Create a module that can analyze a `TrackedDevice` and program execution results to identify equivalent programs through:

1. **Unused Memory Wildcarding**: Mark memory locations that don't affect execution
2. **Dead Register Operation Detection**: Identify meaningless register manipulations  
3. **Register Role Equivalence**: Detect when R0/R1 can be systematically swapped
4. **Output Pattern Classification**: Group programs by output characteristics

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

### Detection Strategy
- Track all memory reads (instructions 9, 10) and jump targets (13, 14, 15)
- Mark unaccessed locations as wildcards
- Consider self-modifying code (stores that affect executed locations)

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

### Implementation Strategy
1. **Backwards Analysis**: Start from consuming operations, trace back to meaningful manipulations
2. **Data Flow Tracking**: Monitor register def-use chains throughout execution
3. **Wildcard Replacement**: Replace dead operation sequences with NOPs or wildcards

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

### Testing Strategy
- **Exhaustive Verification**: Test on small program lengths (3-4) where full enumeration is feasible
- **Spot Checking**: Random sampling to verify equivalence claims
- **Performance Benchmarks**: Ensure optimizations provide measurable speedup