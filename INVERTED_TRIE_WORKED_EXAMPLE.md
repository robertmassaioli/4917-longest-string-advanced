# Inverted Trie Integration: Worked Example

## Overview
This document demonstrates how two discovered wildcard patterns would be integrated into an inverted trie structure to exclude forbidden program candidates during generation.

---

## Pattern 1: Simple Print Loop
```
Original Program: [8,4,13,4,0]
Wildcard Pattern: 8[0-9]1340***********
```

### Pattern Analysis
- **Position 0**: PRINT instruction (value 8) - REQUIRED
- **Position 1**: Any digit 0-9 (operand for PRINT) - FLEXIBLE
- **Position 2**: JMP instruction (value 13) - REQUIRED
- **Position 3**: Jump to position 4 - REQUIRED
- **Position 4**: HALT instruction (value 0) - REQUIRED
- **Positions 5-15**: Wildcards (don't care, unused memory)

This pattern matches 10 different programs (8[0-9]1340[0-15]^11):
- 8,0,13,4,0
- 8,1,13,4,0
- 8,2,13,4,0
- ... (through 8,9,13,4,0)

---

## Pattern 2: Dual Print
```
Original Program: [8,15,8,3,0]
Wildcard Pattern: 8[10-15]8[0-9]0***********
```

### Pattern Analysis
- **Position 0**: PRINT instruction (value 8) - REQUIRED
- **Position 1**: Values 10-15 (operand for first PRINT) - FLEXIBLE
- **Position 2**: PRINT instruction (value 8) - REQUIRED
- **Position 3**: Any digit 0-9 (operand for second PRINT) - FLEXIBLE
- **Position 4**: HALT instruction (value 0) - REQUIRED
- **Positions 5-15**: Wildcards (don't care, unused memory)

This pattern matches 60 different programs (6 × 10):
- 8,10,8,0,0
- 8,10,8,1,0
- ... (6 choices for position 1 × 10 choices for position 3)

---

## Inverted Trie Structure

The inverted trie stores **forbidden** paths. Once we know a program matches a wildcard pattern, we mark all candidates matching that pattern as excluded.

### Trie Node Structure
```haskell
data TrieNode = TrieNode
  { nodeValue       :: Maybe ConstraintSet
  , children        :: Map Int TrieNode  -- Maps value to next node
  , isForbidden     :: Bool              -- True if this path is forbidden
  , forbiddenReason :: Maybe String      -- Which pattern forbids this
  }

data ConstraintSet
  = Required Int                -- Only this value allowed
  | AnyOf [Int]                 -- Any of these values allowed
  | Wildcard                    -- Any value allowed
```

### Building the Trie: Pattern 1

**Input Pattern**: `8[0-9]1340***********`

```
Root
  └─ 8 (Required)
      └─ [0-9] (AnyOf [0,1,2,3,4,5,6,7,8,9])
          ├─ 0 → 13 (Required)
          │        └─ 13 → 4 (Required)
          │                  └─ 4 → 0 (Required)
          │                          └─ 0 [FORBIDDEN: Pattern1]
          ├─ 1 → 13 (Required)
          │        └─ ...similar...
          ├─ 2 → 13 (Required)
          │        └─ ...similar...
          └─ 9 → 13 (Required)
                   └─ ...similar...
```

**Cleaner Representation** (showing the actual trie structure):

```
Root (level -1)
  │
  └─ [0] → 8 (Required 8)
      │
      └─ [1] → {0,1,2,3,4,5,6,7,8,9} (AnyOf)
          │
          └─ [2] → 13 (Required 13)
              │
              └─ [3] → 4 (Required 4)
                  │
                  └─ [4] → 0 (Required 0)
                      │
                      └─ [5+] → Wildcard (any value or none)
                          │
                          └─ [FORBIDDEN: "Pattern1_8[0-9]1340"]
```

**Paths Forbidden**:
- [8, 0, 13, 4, 0, *, *, ...] → All 16^11 continuations forbidden
- [8, 1, 13, 4, 0, *, *, ...] → All 16^11 continuations forbidden
- ... (10 total base patterns)

---

### Building the Trie: Pattern 2

**Input Pattern**: `8[10-15]8[0-9]0***********`

```
Root (level -1)
  │
  └─ [0] → 8 (Required 8)
      │
      └─ [1] → {10,11,12,13,14,15} (AnyOf)
          │
          ├─ [2] → 8 (Required 8)  [for value 10 at position 1]
          │  │
          │  └─ [3] → {0,1,2,3,4,5,6,7,8,9} (AnyOf)
          │      │
          │      └─ [4] → 0 (Required 0)
          │          │
          │          └─ [5+] → Wildcard
          │              │
          │              └─ [FORBIDDEN: "Pattern2_8[10-15]8[0-9]0"]
          │
          ├─ [2] → 8 (Required 8)  [for value 11 at position 1]
          │  │
          │  └─ [3] → {0,1,2,3,4,5,6,7,8,9} (AnyOf)
          │      │
          │      └─ [4] → 0 (Required 0)
          │          │
          │          └─ [FORBIDDEN: "Pattern2_8[10-15]8[0-9]0"]
          │
          └─ ... (6 total branches for values 10-15)
```

**Paths Forbidden**:
- [8, 10, 8, 0, 0, *, *, ...] → All 16^11 continuations forbidden
- [8, 10, 8, 1, 0, *, *, ...] → All 16^11 continuations forbidden
- ... (60 total base patterns)

---

## Combined Inverted Trie (Both Patterns)

When both patterns are integrated into a single trie, the structure becomes:

```
Root
  │
  └─ [0] → 8 (Required 8)
      │
      ├─ [1] → {0,1,2,3,4,5,6,7,8,9} (AnyOf from Pattern1)
      │   │
      │   └─ [2] → 13 (Required 13)
      │       │
      │       └─ [3] → 4 (Required 4)
      │           │
      │           └─ [4] → 0 (Required 0)
      │               │
      │               └─ [FORBIDDEN: "Pattern1"]
      │
      └─ [1] → {10,11,12,13,14,15} (AnyOf from Pattern2)
          │
          └─ [2] → 8 (Required 8)
              │
              └─ [3] → {0,1,2,3,4,5,6,7,8,9} (AnyOf)
                  │
                  └─ [4] → 0 (Required 0)
                      │
                      └─ [FORBIDDEN: "Pattern2"]
```

**Key Observation**: The two patterns have **non-overlapping position-1 constraints**:
- Pattern 1 allows values 0-9 at position 1
- Pattern 2 allows values 10-15 at position 1
- They can coexist in the same trie without merging

---

## Generation Algorithm Integration

### Candidate Generation Process

When generating candidates for length 5 programs:

```
FOR position = 0 TO 4
  FOR value = 0 TO 15
    IF trie.isForbidden(path_so_far + [value])
      SKIP this candidate
    ELSE
      RECURSE to next position
```

### Example: Checking Candidate [8, 5, 13, 4, 0]

```
Step 1: Check position 0, value 8
  → Root[8] exists, not forbidden
  
Step 2: Check position 1, value 5
  → Root[8][5] exists (5 in {0-9}), not forbidden
  
Step 3: Check position 2, value 13
  → Root[8][5][13] exists, not forbidden
  
Step 4: Check position 3, value 4
  → Root[8][5][13][4] exists, not forbidden
  
Step 5: Check position 4, value 0
  → Root[8][5][13][4][0] exists and is FORBIDDEN
  
Result: [8, 5, 13, 4, 0] is SKIPPED (forbidden by Pattern1)
```

### Example: Checking Candidate [8, 7, 2, 1, 3]

```
Step 1: Check position 0, value 8
  → Root[8] exists, not forbidden
  
Step 2: Check position 1, value 7
  → Root[8][7] exists (7 in {0-9}), not forbidden
  
Step 3: Check position 2, value 2
  → Root[8][7][2] exists? NO!
  → Trie doesn't have this path
  → NOT FORBIDDEN, continue generation
  
Step 4: Check position 3, value 1
  → No constraint, can be any value
  
Step 5: Check position 4, value 3
  → No constraint, can be any value
  
Result: [8, 7, 2, 1, 3] is ALLOWED (doesn't match any forbidden pattern)
```

### Example: Checking Candidate [8, 12, 8, 4, 0]

```
Step 1: Check position 0, value 8
  → Root[8] exists, not forbidden
  
Step 2: Check position 1, value 12
  → Root[8][12] exists (12 in {10-15}), not forbidden
  
Step 3: Check position 2, value 8
  → Root[8][12][8] exists, not forbidden
  
Step 4: Check position 3, value 4
  → Root[8][12][8][4] exists, not forbidden (4 in {0-9})
  
Step 5: Check position 4, value 0
  → Root[8][12][8][4][0] exists and is FORBIDDEN
  
Result: [8, 12, 8, 4, 0] is SKIPPED (forbidden by Pattern2)
```

---

## Memory Efficiency Analysis

### Without Trie (Naive Checking)
To exclude all patterns, you'd need to store patterns as strings:
- Pattern 1: "8[0-9]1340***********" (100+ bytes in string form)
- Pattern 2: "8[10-15]8[0-9]0***********" (150+ bytes in string form)
- Each pattern lookup requires regex matching: O(pattern_length)

### With Inverted Trie
- Pattern 1 contributes: 6 nodes (8 → {0-9} → 13 → 4 → 0 → forbidden marker)
- Pattern 2 contributes: 8 nodes (8 → {10-15} → 8 → {0-9} → 0 → forbidden marker)
- Total nodes ≈ 14 nodes (significant sharing at root)
- Each lookup: O(program_length) with early termination
- Much faster than regex matching

---

## Integration with Future Patterns

### Adding Pattern 3: [4,3,9,2,13,0]

```
Root
  │
  └─ [0] → 4 (Required 4)
      │
      └─ [1] → 3 (Required 3)
          │
          └─ [2] → 9 (Required 9)
              │
              └─ [3] → 2 (Required 2)
                  │
                  └─ [4] → 13 (Required 13)
                      │
                      └─ [5] → 0 (Required 0)
                          │
                          └─ [FORBIDDEN: "Pattern3"]
```

This new branch doesn't conflict with Patterns 1 or 2 (different position-0 values). Simply merge into the existing trie.

### Adding Pattern 4: [8,0,13,5,0]

This pattern shares:
- Position 0: 8 (same as Patterns 1 & 2)
- Position 1: 0 (overlaps with Pattern 1's {0-9})
- Position 2: 13 (matches Pattern 1)
- Position 3: 5 (different from Pattern 1's 4, so new branch)

The trie is updated to branch at position 3:

```
Root
  │
  └─ [0] → 8
      │
      └─ [1] → {0-9}
          │
          └─ [2] → 13
              │
              ├─ [3] → 4 → [4] → 0 → [FORBIDDEN: Pattern1]
              └─ [3] → 5 → [4] → 0 → [FORBIDDEN: Pattern4]
```

---

## Summary: How Inverted Trie Enables Live Updates

1. **Efficient Storage**: Shared prefixes reduce memory footprint
2. **O(depth) Lookups**: Checking if a candidate is forbidden is fast
3. **Incremental Updates**: New patterns merge into existing trie in O(pattern_length) time
4. **Early Termination**: If a partial path isn't forbidden, entire subtree is allowed
5. **Reduction Factor Preservation**: Wildcard constraints remain explicit (AnyOf, Required)

The inverted trie structure elegantly supports the iterative discovery loop: as new patterns are discovered, they integrate seamlessly, immediately excluding more candidates in subsequent searches.
