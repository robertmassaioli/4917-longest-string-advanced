# Reasoning: Longest Output Programs by Length

## Session Goal
Use intelligent analysis and reasoning to predict which programs produce the greatest output for each program length, starting with length 3.

---

## Length 3 Programs Analysis

### Instruction Review & Constraints

**Single-Byte Instructions (0-7):**
- `0` - HALT: Terminates execution
- `1` - ADD: R0 = R0 + R1 (no output)
- `2` - SUB: R0 = R0 - R1 (no output)
- `3` - INC R0: R0++ (no output)
- `4` - INC R1: R1++ (no output)
- `5` - DEC R0: R0-- (no output)
- `6` - DEC R1: R1-- (no output)
- `7` - NOP: Ring bell, no output

**Two-Byte Instructions (8-15):**
- `8 x` - PRINT x: Output value x
- `9 x` - LOAD R0 from memory[x]
- `10 x` - LOAD R1 from memory[x]
- `11 x` - STORE R0 to memory[x]
- `12 x` - STORE R1 to memory[x]
- `13 x` - JMP to location x
- `14 x` - JZ: Jump if R0 == 0
- `15 x` - JNZ: Jump if R0 != 0

### Key Insights for Length 3

**Memory Constraint:**
- 3-byte program means only 3 memory locations can be used
- Memory locations beyond the program are implicitly zero
- PC wraps at 16 locations

**Output Generation:**
- Only PRINT (instruction 8) generates output
- PRINT x outputs the 4-bit value x (0-15)
- Character count: 0-9 = 1 char, 10-15 = 2 chars each
- Maximum per PRINT: 2 characters (for values 10-15)

**Termination Requirement:**
- Program MUST halt to be valid
- Only HALT (instruction 0) explicitly terminates
- Or PC could wrap infinitely and loop (INVALID - must terminate)

### Candidate Strategies

#### Strategy 1: Multiple PRINTs in Sequence
Example: `[8, 15, 0]`
- Instruction 0: PRINT 15 → outputs "15" (2 chars)
- Instruction 2: HALT → terminates
- **Total output: 2 characters**
- **Assessment:** Simple, effective, guaranteed to halt

#### Strategy 2: Two PRINTs Before HALT
Could we use: `[8, 15, 8, ...]`?
- NO! This is length 3 minimum:
  - Byte 0: 8 (PRINT opcode)
  - Byte 1: 15 (argument for PRINT)
  - Byte 2: either another instruction or 8, then we need a 4th byte for its argument
  
- Actually, let's reconsider: `[8, 15, 8]` is length 3
  - Byte 0: 8 (PRINT opcode)
  - Byte 1: 15 (argument = PRINT 15)
  - Byte 2: 8 (another PRINT opcode??)
  - **Problem:** Byte 2 = 8 means PRINT, but it needs an argument in byte 3, which doesn't exist (implicitly 0)
  - So this would be: PRINT 15, then PC advances to byte 2 which is PRINT 0
  - Output: "15" + "0" = "150" (3 characters!)
  - PC advances to byte 3 (doesn't exist, beyond program), memory location 3 = 0, which is HALT
  - **Wait, let me verify:** Program length = position of last non-zero + 1 = position 2 + 1 = 3. Correct!
  - **Total output: 3 characters**

#### Strategy 3: Using Loops with Conditional Jumps
- A 3-byte loop would need to maintain state and print
- Example: `[15, 0, 8]` (JNZ 0, ?, PRINT ?)
  - This would need careful setup but seems complex for 3 bytes
  - JNZ 0 jumps to location 0 if R0 != 0, but we need to set R0 first
  - Doesn't seem viable in 3 bytes without prior setup

### Confirmed Best Answer for Length 3

**Program: `[8, 15, 8]`** ✅ VERIFIED
- Byte 0: `8` (PRINT opcode)
- Byte 1: `15` (argument, PRINT 15 → outputs "15")
- Byte 2: `8` (PRINT opcode with implicit arg 0 → outputs "0")
- Memory location 3 onwards: all 0, so implicit HALT
- **Total Output: "150" = 3 characters**

**Test Results:**
- `[8, 15, 8]` → ProgramTerminated 3 ✓
- `[8, 15, 0]` → ProgramTerminated 2 (only one PRINT)
- `[8, 14, 8]` → ProgramTerminated 3 (PRINT 14 = "14", then PRINT 0)
- `[8, 10, 8]` → ProgramTerminated 3 (PRINT 10 = "10", then PRINT 0)

**Key Pattern Discovered:**
The trick is that any two-byte instruction's argument defaults to 0 when the next byte is accessed. So `[8, x, 8]` always produces output of:
- `x` (2 chars for x ≥ 10, 1 char for x ≤ 9)
- Plus `0` (1 char)
- Total: 3 chars for x ∈ [10-15], 2 chars for x ∈ [0-9]

**Why This is Optimal for Length 3:**
- To get 2 PRINT statements in 3 bytes, we need the second PRINT's argument to be implicit
- We can't have 3 separate PRINT statements (would need 6 bytes minimum)
- We can't have looping constructs that would increase output (would need setup bytes)

---

## Length 4 Programs Analysis

### Strategy Considerations

For length 4, we have 4 bytes to work with. Let's explore options:

**Option 1: Three PRINT statements**
- Pattern: `[8, x, 8, y]` where y is any value
  - Byte 0-1: PRINT x
  - Byte 2-3: PRINT y
  - Would output: x (1-2 chars) + y (1-2 chars) = 2-4 chars total
  - But we need termination! After PRINT y, PC goes to byte 4, which is 0 (HALT)
  - Wait, program length = last non-zero + 1. If byte 3 is non-zero, length = 4. Byte 4 is implicitly 0.
  - Let's check: `[8, 15, 8, 15]`
    - PRINT 15 → "15"
    - PRINT 15 → "15"
    - Next instruction at byte 4 is 0 (HALT)
    - Total: 4 characters

**Option 2: Using loops efficiently**
- Could we set R0 and loop with JNZ?
- Example: `[3, 8, 15, 15]` (INC R0, PRINT 15, JNZ 1)
  - Byte 0: INC R0 → R0 = 1
  - Byte 1: PRINT 15 (arg in byte 2)
  - Byte 2: 15 is the argument for PRINT (value 15 → "15")
  - Byte 3: JNZ 1 (arg in byte 4, which is implicit 0)
  - JNZ with arg 0 doesn't work properly...
  - This doesn't seem viable

**Option 3: Maximize highest values**
- `[8, 15, 8, 15]` → PRINT 15, PRINT 15 → "15" + "15" = 4 chars
- `[8, 14, 8, 14]` → PRINT 14, PRINT 14 → "14" + "14" = 4 chars
- Any combination `[8, a, 8, b]` where a,b ≥ 10 → 4 chars total

### Confirmed Best Answer for Length 4

**Program: `[8, 15, 8, 15]`** (or any `[8, a, 8, b]` with a,b ≥ 10) ✅ VERIFIED
- **Total Output: 4 characters**

**Test Results:**
- `[8, 15, 8, 15]` → ProgramTerminated 4 ✓
- `[8, 15, 8, 10]` → ProgramTerminated 4 ✓
- `[8, 15, 8, 9]` → ProgramTerminated 3 (9 is only 1 char)

**Critical Insight:**
The pattern `[8, a, 8, b, ...]` gives us 2 PRINT statements per 4 bytes, outputting 4 characters when both values are ≥ 10.

**Can we beat 4 characters with loops?**
To use a loop, we'd need:
1. A PRINT statement (2 bytes)
2. A jump instruction (2 bytes)
3. Some way to eventually terminate

For example: `[8, 15, 13, 0]` = PRINT 15, JMP 0
- This creates an infinite loop! Not valid.

What about conditional jumps? `[3, 15, 2, 8]`... wait, let me think systematically about what's possible in 4 bytes with loops.

Actually, in 4 bytes, any loop would need to:
- Execute at least one PRINT (2 bytes)
- Have a jump back (2 bytes)
- But we have no space left for termination logic!

**Conclusion:** Loops cannot beat the simple 2-PRINT approach for length 4.

---

## Length 5 Programs Analysis

### Emerging Pattern Recognition

For lengths 3-4, we've achieved:
- Length 3 → 3 characters
- Length 4 → 4 characters

This suggests a pattern: **Can we achieve N characters for length N?**

For length 5, let's explore:

**Option 1: Extending the PRINT chain**
- `[8, 15, 8, 15, 8]` 
  - PRINT 15 → "15" (2 chars)
  - PRINT 15 → "15" (2 chars)
  - PRINT 0 (implicit arg) → "0" (1 char)
  - Total: 5 characters ✓

**Option 2: Can loops help us exceed 5?**
Let's think about a simple loop:
- `[3, 8, 15, 15, 0]` = INC R0, PRINT 15, JNZ 0, [implicit 0]
  - Wait, JNZ is instruction 15, needs argument at next position
  - Byte 0: `3` = INC R0 → R0 = 1
  - Byte 1: `8` = PRINT (needs arg at byte 2)
  - Byte 2: `15` = arg for PRINT → outputs "15" (2 chars)
  - Byte 3: `15` = JNZ (needs arg at byte 4)
  - Byte 4: `0` = arg for JNZ → jump to location 0 if R0 != 0
  - Since R0 = 1, jump to 0
  - Byte 0: INC R0 → R0 = 2
  - ... this creates an infinite loop with R0 incrementing forever!

What if we decrement instead? `[5, 8, 15, 14, 0]`
- Byte 0: `5` = DEC R0 → R0 = 15 (underflow from 0)
- Still non-zero, would loop forever...

**Key Realization:** To have a terminating loop in 5 bytes, we need:
1. Setup (1 byte for single-byte instruction)
2. PRINT (2 bytes)
3. Conditional jump (2 bytes)
4. Total = 5 bytes, but the loop body has no way to decrease toward termination!

### Preliminary Best Answer for Length 5

**Program: `[8, 15, 8, 15, 8]`** (or similar with values ≥ 10)
- **Total Output: 5 characters**

---

## Pattern Hypothesis: Length N → N Characters (Linear Growth)

Based on our analysis:
- Length 3: 3 chars via `[8, 15, 8]`
- Length 4: 4 chars via `[8, 15, 8, 15]`
- Length 5: 5 chars via `[8, 15, 8, 15, 8]`

**The pattern:** `[8, a₁, 8, a₂, 8, a₃, ..., 8, aₖ, 8, ...]` where each aᵢ ≥ 10

This achieves **exactly N characters for length N** by maximizing PRINT density!

**Can we beat linear growth with loops?**

The challenge: A useful loop needs:
- Loop body with PRINT(s)
- Termination condition that eventually triggers
- Counter setup/modification

Minimum bytes for a productive loop:
- Counter setup: 1+ bytes
- PRINT: 2 bytes
- Conditional jump: 2 bytes
- = 5 bytes minimum

But with 5 bytes, we can only loop once or twice before needing sophisticated termination logic that doesn't fit!

---

---

## BREAKTHROUGH: Loops Beat Linear Growth!

### Critical Discovery: Program `[3, 8, 15, 15]` for Length 4

Testing revealed that `[3, 8, 15, 15]` produces **32 characters** vs. the linear pattern's 4 characters!

**How it works:**
- Byte 0: `3` = INC R0 → R0 = 1
- Byte 1: `8` = PRINT (opcode, needs arg at byte 2)
- Byte 2: `15` = argument for PRINT → outputs "15" (2 chars)
- Byte 3: `15` = JNZ 0 (opcode, needs arg at byte 4)
- Byte 4: implicit 0 = argument for JNZ → "jump to 0 if R0 != 0"
- Since R0 = 1, jumps to byte 0
- Byte 0: INC R0 → R0 = 2
- Byte 2: PRINT 15 → outputs "15" again (2 chars)
- Byte 3: JNZ 0 → jump to 0 (R0 = 2, non-zero)
- This repeats! Each loop iteration prints "15" (2 chars)
- **R0 grows indefinitely: 1, 2, 3, 4, ... until overflow wraps it to 0**
- In 4-bit arithmetic, R0 overflows after 15 → becomes 0
- When R0 = 0, JNZ 0 doesn't jump, falls through to byte 5 (implicit 0 = HALT)
- **Total iterations: 15 (R0 = 1 to 15)**
- **Total output: 15 × 2 = 30 characters**

Wait, we measured 32. Let me recalculate... The loop runs while R0 != 0:
- R0 starts at 0
- INC R0 → R0 = 1 (print "15", 2 chars)
- INC R0 → R0 = 2 (print "15", 2 chars)
- ...continuing...
- INC R0 → R0 = 15 (print "15", 2 chars)
- INC R0 → R0 = 0 (print "15", 2 chars) - this is the 16th iteration!
- Now JNZ 0 with R0 = 0 → doesn't jump, falls through
- **Total: 16 iterations × 2 chars = 32 characters** ✓

This is a **16x improvement** over the linear approach!

### Key Insight: Loop-Based Programs Scale Exponentially

The pattern `[INC R0, PRINT x, JNZ 0]` where x ≥ 10 gives:
- Output per iteration: 2 characters (since x ≥ 10)
- Iterations: 16 (one full wrap of 4-bit counter)
- Total output: **32 characters**
- **This works for ANY program length ≥ 4!**

Actually, let me verify: this uses only 4 bytes. For length 4, we get 32 chars.

Can we do better with length 5? What if we add another instruction?

---

## Length 5 Analysis

For length 5, we still get 32 characters with `[4, 3, 8, 15, 15]`:
- INC R1 (doesn't affect loop)
- INC R0
- PRINT 15
- JNZ 0
- 16 iterations × 2 chars = 32 chars

The extra byte doesn't help much if it's just another setup instruction.

## Length 6: Multiple PRINTs in Loop Body!

**MAJOR DISCOVERY: `[3, 8, 15, 8, 15, 15]` produces 64 characters!**

**How it works:**
- Byte 0: `3` = INC R0 → R0++
- Byte 1-2: PRINT 15 → "15" (2 chars)
- Byte 3-4: PRINT 15 → "15" (2 chars)
- Byte 5: `15` = JNZ (arg at byte 6, implicit 0) → jump to 0 if R0 != 0
- Loop body: 2 PRINTs = 4 chars per iteration
- Total iterations: 16
- **Total output: 16 × 4 = 64 characters**

**General Pattern:**
`[INC R0, PRINT x₁, PRINT x₂, ..., PRINT xₖ, JNZ 0]`
- Loop iterations: 16 (full 4-bit wrap)
- Output per iteration: 2k characters (if all xᵢ ≥ 10)
- Total output: **32k characters**

For length N:
- Setup: 1 byte (INC R0)
- Print statements: (N - 3) / 2 PRINTs (each takes 2 bytes)
- Jump back: 2 bytes (JNZ 0 with implicit arg)
- Number of PRINTs in loop: ⌊(N - 3) / 2⌋
- **Total output: 16 × 2 × ⌊(N - 3) / 2⌋ = 32⌊(N - 3) / 2⌋**

Wait, let me recalculate for length 6:
- N = 6
- Bytes: [INC, PRINT, arg, PRINT, arg, JNZ] + implicit arg for JNZ
- PRINTs: 2
- Output: 16 × 4 = 64 ✓

## Length 7 Analysis

Length 7 doesn't support loops efficiently:
- [3, 8, 15, 8, 15, 8, 15] = INC R0, PRINT, PRINT, PRINT (but byte 6 is arg for PRINT at byte 5, not JNZ)
- Result: Only 6 characters (3 PRINTs without looping)
- The structure doesn't align for a JNZ instruction

**Key insight:** The jump instruction needs to be positioned such that:
1. It's at an even-indexed byte (opcode position)
2. Its argument is implicit (the next byte after program end, which is 0)

## Length 8: Three PRINTs in Loop!

**DISCOVERY: `[3, 8, 15, 8, 15, 8, 15, 15]` produces 96 characters!**

**How it works:**
- Byte 0: `3` = INC R0
- Byte 1-2: PRINT 15 → "15" (2 chars)
- Byte 3-4: PRINT 15 → "15" (2 chars)
- Byte 5-6: PRINT 15 → "15" (2 chars)
- Byte 7: `15` = JNZ (arg at byte 8, implicit 0)
- Loop body: 3 PRINTs = 6 chars per iteration
- Total iterations: 16
- **Total output: 16 × 6 = 96 characters**

## Pattern Recognition: The General Formula

For even-length programs N ≥ 4:
- Structure: `[3, PRINT x₁, PRINT x₂, ..., PRINT xₖ, 15]` + implicit 0 as JNZ argument
- PRINTs in loop: (N - 2) / 2
- Characters per iteration: 2 × (N - 2) / 2 = (N - 2)
- Total iterations: 16
- **Total output: 16 × (N - 2) = 16N - 32 characters**

**Verification:**
- N = 4: 16 × 4 - 32 = 64 - 32 = 32 ✓
- N = 6: 16 × 6 - 32 = 96 - 32 = 64 ✓
- N = 8: 16 × 8 - 32 = 128 - 32 = 96 ✓

**For odd-length programs:**
- N = 3: Linear pattern gives 3 chars
- N = 5: Loop pattern gives 32 chars (INC + PRINT + JNZ, with implicit arg)
- N = 7: Linear pattern gives 6 chars (can't fit proper JNZ structure)

Wait, N = 5 should use pattern `[INC, PRINT x, JNZ 0]` which is only 4 bytes, so program length = 4, not 5.

Let me reconsider: For N = 5, we could do `[3, 8, 15, 14, 0]` but that's not looping...
Or `[4, 3, 8, 15, 15]` which is INC R1, INC R0, PRINT, JNZ - that works and gives 32 chars.

## Optimal Programs Summary

### Complete Pattern Analysis

**For ALL lengths N ≥ 4:**

The optimal pattern is:
```
[setup_byte(s), 3, PRINT x₁, PRINT x₂, ..., PRINT xₖ, 15]
```
where:
- Setup bytes: Any single-byte instructions that don't break the loop (e.g., 1, 4, 7)
- `3` = INC R0 (the counter)
- PRINTs: Each is 2 bytes (opcode 8 + argument ≥ 10 for 2 chars)
- `15` = JNZ opcode (argument is implicit 0 at position N, causing jump to byte 0)

**Formula:**
- Even N: `[3, PRINT, PRINT, ..., PRINT, 15]` → (N-2)/2 PRINTs
- Odd N: `[setup, 3, PRINT, PRINT, ..., PRINT, 15]` → (N-3)/2 PRINTs
- Total PRINTs = ⌊(N-2)/2⌋
- **Output = 16 × 2 × ⌊(N-2)/2⌋ characters**

Simplified for even N: **Output = 16(N-2) = 16N - 32**
Simplified for odd N: **Output = 16(N-3) = 16N - 48**

### Verified Results

| Length | Program | Output | Formula Check |
|--------|---------|--------|---------------|
| 3 | [8, 15, 8] | 3 | Linear (no loop) |
| 4 | [3, 8, 15, 15] | 32 | 16×4-32 = 32 ✓ |
| 5 | [4, 3, 8, 15, 15] | 32 | 16×5-48 = 32 ✓ |
| 6 | [3, 8, 15, 8, 15, 15] | 64 | 16×6-32 = 64 ✓ |
| 7 | [4, 3, 8, 15, 8, 15, 15] | 64 | 16×7-48 = 64 ✓ |
| 8 | [3, 8, 15, 8, 15, 8, 15, 15] | 96 | 16×8-32 = 96 ✓ |
| 9 | [1, 3, 8, 15, 8, 15, 8, 15, 15] | 96 | 16×9-48 = 96 ✓ |
| 10 | [3, 8, 15, 8, 15, 8, 15, 8, 15, 15] | 128 | 16×10-32 = 128 ✓ |
| 11 | [1, 3, 8, 15, 8, 15, 8, 15, 8, 15, 15] | 128 | 16×11-48 = 128 ✓ |
| 12 | [3, 8, 15, 8, 15, 8, 15, 8, 15, 8, 15, 15] | 160 | 16×12-32 = 160 ✓ |

### Why This Works

1. **Loop structure:** INC R0 at start → increments counter from 0 to 15, then wraps to 0
2. **16 iterations:** 4-bit register wraps after 16 increments (0→1→...→15→0)
3. **JNZ termination:** When R0 becomes 0, JNZ doesn't jump, falls through to implicit HALT
4. **Maximizing PRINTs:** Pack as many PRINT statements as possible in the loop body
5. **2 chars per PRINT:** Use values ≥ 10 (10-15) for maximum output

### Length 3 Exception

Length 3 cannot support a proper loop:
- Best: `[8, 15, 8]` = 3 characters (linear)
- Loop would need 4 bytes minimum

## Final Formula Summary

**For N ≥ 4:**
- **Even N:** Output = **16N - 32** characters
- **Odd N:** Output = **16N - 48** characters

**Simplified:** Output = **16⌊(N-2)/2⌋ × 2 = 32⌊(N-2)/2⌋** characters

