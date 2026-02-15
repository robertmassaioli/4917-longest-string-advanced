# 4917 Longest Output Programs: Pattern Analysis

## Executive Summary

Through systematic testing and analysis, we've discovered three fundamentally different optimal patterns for generating maximum output from 4917 microprocessor programs:

1. **Linear PRINT Chain** (Length 3): Simple chaining of PRINT instructions
2. **INC R0 Loop Pattern** (Length 4-12): Counter-based loop with implicit termination
3. **ADD/SUB Loop Pattern** (Length 5-7): Superior R1-based counter using ADD/SUB operations

The ADD/SUB pattern nearly **doubles output** compared to the INC R0 approach for certain lengths.

---

## Pattern 1: Linear PRINT Chain (Length 3)

**Optimal Program: `[8, 15, 8]`**
- Output: **3 characters** ("15" + "0")
- Limitation: Cannot fit a proper loop in 3 bytes

**How it works:**
- Byte 0-1: PRINT 15 → outputs "15" (2 chars)
- Byte 2: PRINT opcode (8), with implicit arg 0 → outputs "0" (1 char)
- Byte 3+: Implicit HALT

**Key Insight:** Two-byte instructions can use implicit zero as an argument when the next byte is accessed, allowing us to chain multiple PRINTs in minimal space.

---

## Pattern 2: INC R0 Loop (Length 4-12)

**Core Structure:**
```
[setup_byte(s), 3, PRINT x₁, PRINT x₂, ..., PRINT xₖ, 15]
```
Where:
- `setup_byte` = Optional neutral instruction (1 byte) for odd lengths
- `3` = INC R0 (counter initialization)
- `PRINT xᵢ` = Each PRINT is 2 bytes (opcode 8 + arg ≥ 10 for 2-char output)
- `15` = JNZ opcode with implicit 0 argument (jump to byte 0)

**How it works:**
1. INC R0 starts at 0, executes in loop body → R0 becomes 1, 2, 3, ..., 15, 0
2. Each loop iteration executes all PRINT statements
3. When R0 wraps to 0, JNZ doesn't jump → program terminates
4. **Total iterations: 16** (full 4-bit wrap)

**Formula:**
- Even length N: Output = **16(N - 2) = 16N - 32** characters
- Odd length N: Output = **16(N - 3) = 16N - 48** characters

### Verified Results (INC R0 Pattern)

| Length | Best Program | Output | Formula |
|--------|--------------|--------|---------|
| 4 | `[3, 8, 15, 15]` | 32 | 16×4-32 = 32 ✓ |
| 5 | `[4, 3, 8, 15, 15]` | 32 | 16×5-48 = 32 ✓ |
| 6 | `[3, 8, 15, 8, 15, 15]` | 64 | 16×6-32 = 64 ✓ |
| 7 | `[4, 3, 8, 15, 8, 15, 15]` | 64 | 16×7-48 = 64 ✓ |
| 8 | `[3, 8, 15, 8, 15, 8, 15, 15]` | 96 | 16×8-32 = 96 ✓ |
| 9 | `[1, 3, 8, 15, 8, 15, 8, 15, 15]` | 96 | 16×9-48 = 96 ✓ |
| 10 | `[3, 8, 15, 8, 15, 8, 15, 8, 15, 15]` | 128 | 16×10-32 = 128 ✓ |
| 11 | `[1, 3, 8, 15, 8, 15, 8, 15, 8, 15, 15]` | 128 | 16×11-48 = 128 ✓ |
| 12 | `[3, 8, 15, 8, 15, 8, 15, 8, 15, 8, 15, 15]` | 160 | 16×12-32 = 160 ✓ |

**Key Observations:**
- Each pair of bytes in the loop adds 4 characters (two 2-char PRINTs)
- Setup bytes (1, 4, 7) don't interfere with the counter
- The formula is completely predictable for any length

---

## Pattern 3: ADD/SUB Loop (Length 5-7+)

**Core Structure:**
```
[setup_byte(s), 4, 1/2, PRINT x₁, PRINT x₂, ..., PRINT xₖ, 15]
```
Where:
- `4` = INC R1 (executed **every iteration in the loop**)
- `1` = ADD R0, R1 (or `2` = SUB R0, R1)
- The rest follows the same PRINT/JNZ structure as Pattern 2

**Revolutionary Insight:**
Unlike INC R0 which only increments in the loop body, INC R1 is executed EVERY iteration, causing R1 to grow (1, 2, 3, ..., 15, 0, 1, ...). This creates a complex interaction with ADD that produces a much longer cycle.

**Execution Example: `[4, 1, 8, 15, 15]` (Length 5)**
```
Iteration 1: R1=0→1, ADD → R0=0+1=1, PRINT 15 → "15"
Iteration 2: R1=1→2, ADD → R0=1+2=3, PRINT 15 → "15"
Iteration 3: R1=2→3, ADD → R0=3+3=6, PRINT 15 → "15"
Iteration 4: R1=3→4, ADD → R0=6+4=10, PRINT 15 → "15"
Iteration 5: R1=4→5, ADD → R0=10+5=15, PRINT 15 → "15"
Iteration 6: R1=5→6, ADD → R0=15+6=21→5 (wraps), PRINT 15 → "15"
Iteration 7: R1=6→7, ADD → R0=5+7=12, PRINT 15 → "15"
... (continues until R0 cycles back to 0)
Total: 31 iterations × 2 chars = 62 characters
```

**Formula:**
The ADD/SUB pattern produces **31 iterations** instead of 16, nearly doubling output for certain lengths.

### Verified Results (ADD/SUB Pattern)

| Length | Best Program | Output | Improvement |
|--------|--------------|--------|-------------|
| 5 | `[4, 1, 8, 15, 15]` | 62 | +30 vs INC R0 (32) |
| 5 | `[4, 2, 8, 15, 15]` | 62 | SUB works equally |
| 6 | `[7, 4, 1, 8, 15, 15]` | 62 | Same as length 5 |
| 7 | `[4, 1, 8, 15, 8, 15, 15]` | 124 | Doubles with 2 PRINTs |

**Critical Pattern:**
- Single INC R1 before ADD/SUB is **essential**
- Multiple INC R1 instructions reduce output (e.g., `[4, 4, 1, 8, 15, 15]` = 30 chars)
- Neutral setup bytes (NOP=7) preserve the 31-iteration cycle
- Interfering setup bytes (INC R0=3) reduce iterations (e.g., from 31 to 29)

**Limitations:**
The ADD/SUB pattern doesn't scale indefinitely. As program length increases:
- Length 5: 62 chars (vs 32 with INC R0)
- Length 6: 62 chars (no improvement over length 5)
- Length 7: 124 chars (scales with additional PRINTs)

This suggests the pattern is optimal for specific length ranges, after which the INC R0 pattern may regain superiority.

---

## Comparison: When to Use Each Pattern

| Length | Best Pattern | Program | Output |
|--------|--------------|---------|--------|
| 3 | Linear | `[8, 15, 8]` | 3 |
| 4 | INC R0 | `[3, 8, 15, 15]` | 32 |
| 5 | **ADD/SUB** | `[4, 1, 8, 15, 15]` | **62** |
| 6 | **ADD/SUB** | `[7, 4, 1, 8, 15, 15]` | **62** |
| 7 | **ADD/SUB** | `[4, 1, 8, 15, 8, 15, 15]` | **124** |
| 8 | INC R0 (likely) | `[3, 8, 15, 8, 15, 8, 15, 15]` | 96 |
| 9+ | INC R0 (likely) | Follow formula | 16N - 48 |

---

## Key Insights & Lessons

### 1. Implicit Arguments Are Powerful
Two-byte instructions in 4917 can use implicit zero arguments, allowing efficient code packing.

### 2. Counter Loop Termination is Elegant
Using a 4-bit counter that wraps naturally from 15→0 creates automatic termination without explicit termination logic.

### 3. R1 Interaction Creates Complex Cycles
Using INC R1 in the loop body (rather than setup) creates non-trivial sequences that produce longer cycles than simple INC R0.

### 4. Multiple Instructions in Loop Body Scale Linearly
Adding more PRINT statements increases output proportionally (each pair adds 4 chars).

### 5. Setup Bytes Must Be Neutral
Setup instructions that modify counter registers reduce iteration count and should be avoided unless necessary for structure.

---

## Open Questions & Future Exploration

1. **Does ADD/SUB pattern continue beyond length 7?** Testing length 8+ with ADD/SUB could reveal extended improvements.

2. **Can we combine patterns?** Could we create hybrid programs that use multiple loops or different strategies at different lengths?

3. **Are there other R1-based patterns?** INC R1 + ADD was revolutionary. What about DEC R1, or INC/DEC combinations?

4. **What about using both registers as counters?** Programs that orchestrate both R0 and R1 might unlock further improvements.

5. **Can memory be leveraged?** Using STORE/LOAD to implement multi-iteration counters or state machines?

---

## Testing Methodology

All programs were verified using the `test-program` CLI command which:
- Runs the program to termination
- Detects infinite loops
- Counts output characters
- Displays optimized program representation with equivalence classes

This ensures all results are empirically validated and replicable.
