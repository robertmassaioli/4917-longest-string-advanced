# Length 10 Programs: Novel Pattern Discovery & Analysis

## Executive Summary

Through systematic exploration of length 10 programs, I discovered a novel pattern that produces **174 characters**—significantly outperforming the baseline INC R0 pattern (128 characters) and matching or exceeding the ADD/SUB patterns from shorter lengths.

**Winner: `[3, 4, 1, 8, 15, 8, 15, 8, 15, 15]` = 174 characters**

---

## The Winning Pattern

### Program Structure
```
[3, 4, 1, 8, 15, 8, 15, 8, 15, 15]
```

### Decoded Instructions
- **Byte 0**: `3` = INC R0
- **Byte 1**: `4` = INC R1  
- **Byte 2**: `1` = ADD (R0 = R0 + R1)
- **Bytes 3-4**: `8, 15` = PRINT 15 (outputs "15", 2 characters)
- **Bytes 5-6**: `8, 15` = PRINT 15 (outputs "15", 2 characters)
- **Bytes 7-8**: `8, 15` = PRINT 15 (outputs "15", 2 characters)
- **Byte 9**: `15` = JNZ 0 (Jump to byte 0 if R0 ≠ 0)

### Execution Flow

Each iteration (starting from byte 0):
1. **INC R0**: R0 ← (R0 + 1) mod 16
2. **INC R1**: R1 ← (R1 + 1) mod 16
3. **ADD**: R0 ← (R0 + R1) mod 16
4. **PRINT 15**: Output "15" (3 times, 6 characters total per iteration)
5. **JNZ 0**: If R0 ≠ 0, jump back to byte 0; else halt

### Iteration Trace

| Iter | R0 (start) | R0 (after +1) | R1 (after +1) | R0 (after ADD) | Output | Halt? |
|------|-----------|---------------|---------------|----------------|--------|-------|
| 1    | 0         | 1             | 1             | 2              | "151515" | No   |
| 2    | 2         | 3             | 2             | 5              | "151515" | No   |
| 3    | 5         | 6             | 3             | 9              | "151515" | No   |
| 4    | 9         | 10            | 4             | 14             | "151515" | No   |
| 5    | 14        | 15            | 5             | 4              | "151515" | No   |
| 6    | 4         | 5             | 6             | 11             | "151515" | No   |
| 7    | 11        | 12            | 7             | 3              | "151515" | No   |
| 8    | 3         | 4             | 8             | 12             | "151515" | No   |
| 9    | 12        | 13            | 9             | 6              | "151515" | No   |
| 10   | 6         | 7             | 10            | 1              | "151515" | No   |
| 11   | 1         | 2             | 11            | 13             | "151515" | No   |
| 12   | 13        | 14            | 12            | 10             | "151515" | No   |
| 13   | 10        | 11            | 13            | 8              | "151515" | No   |
| 14   | 8         | 9             | 14            | 7              | "151515" | No   |
| 15   | 7         | 8             | 15            | 7              | "151515" | No   |
| 16   | 7         | 8             | 0             | 8              | "151515" | No   |
| 17   | 8         | 9             | 1             | 10             | "151515" | No   |
| 18   | 10        | 11            | 2             | 13             | "151515" | No   |
| 19   | 13        | 14            | 3             | 1              | "151515" | No   |
| 20   | 1         | 2             | 4             | 6              | "151515" | No   |
| 21   | 6         | 7             | 5             | 12             | "151515" | No   |
| 22   | 12        | 13            | 6             | 3              | "151515" | No   |
| 23   | 3         | 4             | 7             | 11             | "151515" | No   |
| 24   | 11        | 12            | 8             | 4              | "151515" | No   |
| 25   | 4         | 5             | 9             | 14             | "151515" | No   |
| 26   | 14        | 15            | 10            | 9              | "151515" | No   |
| 27   | 9         | 10            | 11            | 5              | "151515" | No   |
| 28   | 5         | 6             | 12            | 2              | "151515" | No   |
| 29   | 2         | 3             | 13            | **0**          | "151515" | **Yes** |

**Total Output**: 29 iterations × 6 characters = **174 characters**

---

## Mathematical Analysis

### The Recurrence

Define the state after iteration `n`:
```
R0(n) = ((n + 1) + (n + 1)) mod 16  [simplified form]
```

More precisely, the sequence follows:
```
R0(n) = (R0(n-1) + 1 + R1(n)) mod 16
R1(n) = (R1(n-1) + 1) mod 16
```

### Why 29 Iterations?

The pattern cycles when R0 reaches 0 again. Unlike the simpler 31-cycle pattern from length 5 (which used only INC R1 + ADD), this pattern involves **pre-incrementing R0** before the ADD operation, which changes the cycle length.

The sequence R0 follows is:
```
0 → 2 → 5 → 9 → 14 → 4 → 11 → 3 → 12 → 6 → 1 → 13 → 10 → 8 → 7 → 7 → 8 → 10 → 13 → 1 → 6 → 12 → 3 → 11 → 4 → 14 → 9 → 5 → 2 → 0
```

This is a completely different cycle than the 31-iteration ADD/SUB pattern because:
1. We increment R0 **before** the ADD (not just in setup)
2. This creates a different mathematical interaction between the increments and the ADD
3. The cycle length is determined by when the accumulated state returns to 0

---

## Comparison with Other Patterns

| Pattern | Length | Structure | Output | Notes |
|---------|--------|-----------|--------|-------|
| Baseline INC R0 | 10 | `[3, 8, 15, 8, 15, 8, 15, 8, 15, 15]` | 128 | Formula: 16N - 32 |
| ADD/SUB (extended) | 10 | `[4, 1, 8, 15, 8, 15, 8, 15, 8, 15]` | 6 | Doesn't scale well to length 10 |
| **Novel Winner** | **10** | **`[3, 4, 1, 8, 15, 8, 15, 8, 15, 15]`** | **174** | **+46 vs baseline (36% improvement)** |

### Key Insight

The winning pattern combines three techniques:
1. **Pre-loop initialization** of R0 (INC R0 at start)
2. **In-loop register manipulation** (INC R0, INC R1 in loop body)
3. **Multi-register arithmetic** (ADD operating on both incremented values)

This creates a much longer cycle (29 iterations) than simple counter approaches, maximizing output for the given length.

---

## Tested Variations

I tested over 20 novel approaches to find even better patterns:

### Patterns That Achieved 174 Characters (Equivalent Performance)

These all produced the same 174-character output:
- `[3, 4, 1, 8, 15, 8, 15, 8, 15, 15]` - INC R0, INC R1, ADD
- `[5, 6, 1, 8, 15, 8, 15, 8, 15, 15]` - DEC R0, DEC R1, ADD
- `[3, 6, 2, 8, 15, 8, 15, 8, 15, 15]` - INC R0, DEC R1, SUB
- `[5, 4, 2, 8, 15, 8, 15, 8, 15, 15]` - DEC R0, INC R1, SUB
- `[4, 3, 1, 8, 15, 8, 15, 8, 15, 15]` - INC R1, INC R0, ADD (reversed order)

### Patterns That Underperformed

- `[3, 4, 4, 1, 8, 15, 8, 15, 15, 15]` (Multiple INC R1): 4 chars
- `[3, 4, 1, 1, 8, 15, 8, 15, 15, 15]` (ADD twice): 4 chars
- `[4, 4, 1, 8, 15, 8, 15, 8, 15, 15]` (Double INC R1, no INC R0): 90 chars
- `[3, 3, 4, 1, 8, 15, 8, 15, 15, 15]` (Double INC R0): 4 chars
- `[3, 4, 7, 1, 8, 15, 8, 15, 15, 15]` (NOP in loop): 4 chars

---

## Why This Pattern Works So Well

1. **Longer cycle**: The 29-iteration cycle is significantly longer than the baseline 16-iteration INC R0 cycle
2. **Efficient space usage**: Uses exactly 10 bytes with 3 PRINT statements per iteration
3. **Register interaction**: The combination of incrementing both registers before ADD creates a complex, non-repeating sequence
4. **Modular arithmetic**: The 4-bit constraints create the specific 29-iteration periodicity

---

## Equivalence Classes

The pattern exhibits equivalence across multiple dimensions:

- **PRINT values**: Can use any 2-character operand (10-15) with identical cycle
  - `[3, 4, 1, 8, 10, 8, 10, 8, 10, 15]` = 174 chars
  - `[3, 4, 1, 8, 14, 8, 14, 8, 14, 15]` = 174 chars

- **Register operations**: Multiple arithmetic operations preserve the 29-cycle
  - INC R0 + INC R1 + ADD = 174 chars
  - DEC R0 + DEC R1 + ADD = 174 chars
  - INC R0 + DEC R1 + SUB = 174 chars
  - DEC R0 + INC R1 + SUB = 174 chars

This suggests the cycle length depends on the **combination of operations** rather than the specific increment direction.

---

## Potential Extensions

1. **Length 11+**: Could this pattern extend further? The 29-cycle is fundamental, so additional bytes would primarily add more PRINT statements or setup bytes.

2. **Multiple loops**: Could we create programs with two independent loops using different cycle mechanisms?

3. **Memory-based counters**: Using STORE/LOAD to create secondary state machines?

4. **Instruction self-modification**: Programs that overwrite themselves to create dynamic behavior?

---

## Conclusion

The length 10 exploration revealed that **combining in-loop register manipulation with multi-register arithmetic creates significantly longer cycles** than simple counter approaches. The novel pattern achieves 174 characters—a **36% improvement** over the baseline INC R0 pattern.

This suggests that for longer program lengths, the optimal strategy may not be to follow a single formula but to search for register interaction patterns that create longer execution cycles.

The equivalence class of patterns producing 174 characters indicates that this result is robust across multiple arithmetic operations and print values, suggesting it may be a local optimum for length 10 programs.
