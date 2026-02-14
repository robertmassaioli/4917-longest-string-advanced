# Generative Search Proposal: Guided Program Generation with Wildcard Constraints

## Executive Summary

Current approach: **Generate all programs → Analyze each → Cache patterns → Reject matches**

Proposed direction: **Live-integrate wildcard patterns into generation → Generate only candidates that WON'T match existing patterns → Apply heuristics to prioritize promising search spaces**

This document outlines a unified interface and five distinct approaches to this problem, ranging from simple to sophisticated.

---

## Problem Statement & Motivation

The current optimized search system exhausts the full search space (16^N programs for length N), then filters out programs matching cached wildcard patterns. This is inherently inefficient because:

1. **Generation waste**: We generate candidates we'll immediately reject
2. **Pattern matching overhead**: Every program is checked against all cached patterns via bitmap matching
3. **No guidance**: Search proceeds uniformly rather than targeting high-value regions
4. **Scalability ceiling**: As wildcard cache grows, filtering cost increases

The proposed generative approach would:
- **Merge constraint generation with pattern matching**: Build only non-matching programs
- **Add heuristics**: Prioritize program spaces likely to produce longer output
- **Reduce execution pressure**: Fewer total programs to evaluate
- **Scale beneficially**: More patterns = better pruning = fewer candidates to generate

---

## Common Interface Design

All proposed approaches share a unified CLI command structure and pattern integration protocol:

### CLI Command

```bash
stack exec cli4917 -- gen-search --length N [OPTIONS]
```

**Standard Options:**
- `--length N`: Program length to search
- `--cache FILE`: Persistent wildcard cache file
- `--fresh`: Start with empty cache (ignore file)
- `--heuristic HEURISTIC`: Guide generation strategy (see approach-specific options)
- `--max-candidates LIMIT`: Maximum programs to generate (if applicable)
- `--verbose`: Detailed progress reporting
- `--timeout SECONDS`: Kill search after N seconds

**Output Format (standardized across all approaches):**
```
🚀 Starting generative search for length N programs
Pattern cache loaded: M patterns (X% reduction factor)
Generation strategy: APPROACH_NAME

[progress output - approach specific]

🎯 Search Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Generation Performance:
  Candidate programs generated: X
  Programs executed: Y
  Programs skipped (matched patterns): Z
  Cache hit reduction: W%
  
🏆 Best Result:
  Program: [...]
  Output: N characters
```

### Pattern Integration Protocol

Each approach must implement this protocol for incorporating new wildcard patterns:

```haskell
-- Common interface all approaches must provide
class GenerativeCandidateGenerator where
    -- Create generator with initial cache
    newGenerator :: CacheConfig -> OptimizedProgram -> IO GeneratorState
    
    -- Add newly-discovered pattern to live generation system
    -- Called each time a program is analyzed and cached
    integratePattern :: GeneratorState -> OptimizedProgram -> IO GeneratorState
    
    -- Get next batch of candidate programs that won't match any cached patterns
    -- Returns candidates OR signal that search space is exhausted
    getNextCandidates :: GeneratorState -> Int -> IO (Maybe [CandidateProgram])
    
    -- Query statistics
    getGenerationStats :: GeneratorState -> GenerationStats

data GenerationStats = GenerationStats
    { patternsIntegrated :: Int
    , candidatesGenerated :: Int
    , candidatesCached :: Int  -- Skipped due to matching cached patterns
    , estimatedSearchSpaceRemaining :: Double
    , averageGenerationTimePerCandidate :: Double
    } deriving (Show)
```

### Pattern Integration Strategy

**Critical assumption**: Patterns are discovered incrementally during search and must be integrated in real-time.

**Integration flow:**
1. Run program → Get output
2. If output > 0 and terminates: Analyze → Generate OptimizedProgram with wildcard pattern
3. **[NEW]** Integrate pattern into generator's constraint model
4. **[NEW]** Regenerate candidate list (skip programs matching new pattern)
5. Continue searching with refined candidate set

**Key insight**: Each new pattern reduces the search frontier. Eventually, the search space becomes either exhausted or too heavily constrained to explore further.

---

## Five Approach Options

### OPTION 1: Bitmap Constraint Propagation (Simple)

**Complexity:** ⭐⭐☆☆☆ Low  
**Chance of Success:** ⭐⭐⭐⭐☆ High (80%)  
**Expected Performance Win:** 2x-5x vs current optimized-search  
**Implementation Effort:** 1-2 weeks  

#### Overview
Convert each wildcard pattern into a "constraint mask" at each memory position. During generation, skip any candidate that would satisfy all position constraints of any cached pattern.

#### How It Works

```
Wildcard Pattern Example:
  Position 0: Required(8)  [bit mask: 0b0000_0001_0000_0000]
  Position 1: AnyOf([10-15]) [bit mask: 0b1111_1100_0000_0000]
  Position 2: Wildcard       [bit mask: 0b1111_1111_1111_1111]
  ... (remaining: all Wildcard)

Constraint Mask for Pattern:
  masks[0] = 0x0100 (only byte 8 allowed)
  masks[1] = 0xFC00 (only bytes 10-15 allowed)
  masks[2] = 0xFFFF (any byte allowed)

Generation Algorithm:
  For each candidate [b0, b1, b2, ...]:
    matches = True
    For pattern in cachedPatterns:
      if NOT (candidate[i] matches pattern.masks[i] for all i):
        matches = False
        break
    if NOT matches:
      yield candidate
```

#### Pattern Integration
When a new pattern arrives, append its constraint masks to the set. On next generation batch request, re-filter candidates against the expanded mask set.

**Pros:**
- Straightforward bit manipulation
- Reuses existing bitmap matching logic
- Can run lazily (generate-on-demand)
- Easy to understand and debug

**Cons:**
- Generates all 16^N candidates in memory first (huge memory overhead for N>6)
- Filtering still O(P*16^N) where P = number of patterns
- No search guidance—still explores uniformly
- Pattern integration requires regenerating entire candidate set

**Implementation Sketch:**
```haskell
-- Generate all programs and filter against patterns
generateNonMatchingCandidates :: Int -> [OptimizedProgram] -> [[Byte]]
generateNonMatchingCandidates length patterns =
  let allCandidates = generateAllPrograms length
      patternBitmasks = map wildcardPatternBitmask patterns
  in filter (\prog -> not $ any (matchesPattern prog) patterns) allCandidates

-- Integrate new pattern by appending to pattern list
integratePattern :: GeneratorState -> OptimizedProgram -> IO GeneratorState
integratePattern state pattern = 
  return state { cachedPatterns = pattern : cachedPatterns state }
```

---

### OPTION 2: Constraint Satisfaction Problem (Moderate)

**Complexity:** ⭐⭐⭐☆☆ Moderate  
**Chance of Success:** ⭐⭐⭐⭐⭐ Very High (92%)  
**Expected Performance Win:** 5x-15x vs current optimized-search  
**Implementation Effort:** 2-3 weeks  

#### Overview
Model the search space as a constraint satisfaction problem (CSP). Each pattern becomes a set of exclusion constraints. Use CSP solver to enumerate only solutions that violate at least one constraint per pattern (i.e., candidates that DON'T match any cached pattern).

#### How It Works

```
CSP Domain Setup:
  Variables: x[0], x[1], ..., x[length-1]
  Domains: [0..15] for each x[i]
  
Constraints (from cached patterns):
  Pattern 1: (x[0]∈{8}) ∧ (x[1]∈{10,11,12,13,14,15}) ∧ (x[2]∈[0..15])
  Pattern 2: (x[0]∈{0,1,2,7}) ∧ (x[1]∈[0..15]) ∧ (x[3]∈{0})
  ...
  
Goal: Find all assignments where each pattern constraint is VIOLATED
  NOT (Pattern 1 is satisfied) AND
  NOT (Pattern 2 is satisfied) AND
  ...

Generation Algorithm:
  cspSolver = initCSP(variables, domains, constraints)
  while cspSolver.hasNextSolution():
    candidate = cspSolver.nextSolution()
    yield candidate
```

#### Pattern Integration
Add new pattern as additional exclusion constraint. CSP solver re-optimizes domain pruning and constraint propagation automatically.

**Pros:**
- Mathematically rigorous—guarantees no missed candidates
- Constraint propagation automatically prunes search space
- Patterns integrate naturally (add constraint, re-solve)
- Solver can apply sophisticated heuristics (arc consistency, etc.)
- More elegant than brute-force filtering

**Cons:**
- CSP solvers (even specialized ones) are complex to implement/integrate
- Requires Haskell CSP library (may need to write custom solver)
- Constraint propagation overhead at each step
- Pattern integration requires re-solving constraints (non-trivial cost)
- May still generate many candidates if patterns are sparse

**Implementation Sketch:**
```haskell
-- Model patterns as exclusion constraints
type Constraint = [Byte] -> Bool  -- Returns True if violated (CANDIDATE)

fromWildcardPatternToConstraint :: OptimizedProgram -> Constraint
fromWildcardPatternToConstraint optProg = 
  \candidate -> not $ matchesPattern candidate optProg

-- CSP-based generation
generateViaCsp :: Int -> [OptimizedProgram] -> IO [[Byte]]
generateViaCsp length patterns = do
  let constraints = map fromWildcardPatternToConstraint patterns
      domains = replicate length [0..15]
  cspResults <- solveCsp domains constraints
  return cspResults
```

---

### OPTION 3: Inverted Trie Index (Advanced)

**Complexity:** ⭐⭐⭐⭐☆ Advanced  
**Chance of Success:** ⭐⭐⭐⭐☆ High (85%)  
**Expected Performance Win:** 10x-30x vs current optimized-search  
**Implementation Effort:** 2-4 weeks  

#### Overview
Build an **inverted trie** where each node represents a "forbidden candidate" set. Rather than storing what IS allowed, store what is FORBIDDEN. Generate candidates by traversing the trie and skipping branches that lead to forbidden programs.

#### How It Works

```
Standard Trie (current system):
  Root
   ├─ 8 ──────────── [optional: PRINT operand branch]
   │   ├─ 10,11,...,15 ─ [match: Pattern 1]
   │   └─ 0-7 ────────── [no match]
   ├─ 0 ────────────── [HALT branch]
   │   └─ ... ─────── [various branches]
   └─ 1-7,9-15 ─────── [other instructions]

Inverted Trie (forbidden programs):
  Root
   ├─ [forbidden at pos 0: 8]
   │   ├─ [forbidden at pos 1: 10..15]
   │   │   └─ [forbidden at pos 2: any]
   │   │       └─ → FORBIDDEN CANDIDATE: [8, 10-15, *, *, ...]
   │   │
   │   └─ [allowed at pos 1: 0-9] → allowed to proceed deeper
   ├─ [allowed at pos 0: 0-7, 9-15] → allowed to proceed
   ...

Generation by Traversal:
  function generateNonForbidden(node, position, program):
    if position == length:
      yield program (reached leaf, not forbidden)
      return
    
    for byte in [0..15]:
      if node.forbiddenSet.contains(byte):
        skip this byte (would match a pattern)
      else:
        nextNode = node.childAtByte(byte)  // May be None
        if nextNode exists:
          generateNonForbidden(nextNode, position+1, program+[byte])
        else:
          // No prohibition at deeper levels
          yield program + [byte] + padding
```

#### Pattern Integration
When new pattern arrives, compute the set of programs it forbids and insert those into the inverted trie. Future traversals automatically avoid those programs.

**Pros:**
- Generates only candidates that won't match (lazy evaluation)
- Very efficient after patterns are integrated (branch skipping)
- Natural fit for incremental pattern addition
- Can provide early termination signals (e.g., "this branch entirely forbidden")
- Good memory efficiency (only stores forbidden paths)

**Cons:**
- Complex trie structure to implement correctly
- High setup cost initially (building inverted index)
- Traversal still requires checking at each level
- May generate candidates in non-intuitive order (harder to add heuristics)
- Bugs in trie navigation could silently skip valid candidates

**Implementation Sketch:**
```haskell
data InvertedTrieNode = InvertedTrieNode
  { forbiddenAtThisLevel :: Set.Set Byte  -- Bytes that would match a pattern here
  , childNodes :: Map.Map Byte InvertedTrieNode
  , isForbiddenLeaf :: Bool  -- Entire subtree forbidden
  }

-- Generate by traversing inverted trie
generateNonForbidden :: InvertedTrieNode -> Int -> Int -> [[Byte]] -> [[Byte]]
generateNonForbidden node pos length acc
  | pos == length = [reverse acc]  -- Reached leaf, this candidate is allowed
  | isForbiddenLeaf node = []  -- Entire branch is forbidden
  | otherwise =
      concatMap (\byte -> 
        if byte `Set.member` forbiddenAtThisLevel node
          then []  -- Skip this byte
          else case Map.lookup byte (childNodes node) of
            Just nextNode -> generateNonForbidden nextNode (pos+1) length (byte:acc)
            Nothing -> [reverse acc ++ [byte]]  -- No deeper prohibition
        ) [0..15]
```

---

### OPTION 4: Heuristic-Guided Generation with Pruning (Advanced+)

**Complexity:** ⭐⭐⭐⭐⭐ Very Advanced  
**Chance of Success:** ⭐⭐⭐⭐☆ High (82%)  
**Expected Performance Win:** 15x-50x vs current optimized-search  
**Implementation Effort:** 3-5 weeks  

#### Overview
Combine constraint filtering (Option 2) with **heuristic ordering** to explore high-value regions first. Heuristics predict which programs are likely to produce longer output and prioritize their exploration.

#### How It Works

```
Heuristic Scoring:
  Each candidate gets a priority score based on:
  
  1. Jump Instruction Density:
     score += 10 * (count of jumps / program_length)
     Rationale: More jumps = more loop potential = longer execution = more output
  
  2. Print Instruction Presence:
     score += 20 * (count of print instructions)
     Rationale: Each PRINT directly produces output
  
  3. Arithmetic Operation Count:
     score += 5 * (count of ADD/SUB/INC/DEC)
     Rationale: Arithmetic enables larger PRINT values
  
  4. Constraint Reduction:
     score -= 3 * (number of positions matching existing patterns)
     Rationale: More constrained = less likely to be novel
  
  5. Memory Diversity:
     score += 2 * (count of distinct memory positions accessed)
     Rationale: More diverse memory use = more complex execution
  
  Example: [8, 15, 13, 0] 
    - 1 PRINT: +20
    - 1 JMP: +10
    - 1 HALT: 0
    - 0 matching constraints: 0
    - Memory positions {0,1,2,3}: +8
    - Total: 38 (high priority)

Generation Algorithm:
  candidates = generateNonMatchingCandidates(length, patterns)
  priorityQueue = []
  
  for candidate in candidates:
    score = computeHeuristic(candidate, patterns)
    priorityQueue.insert(candidate, score)
  
  while priorityQueue not empty:
    candidate = priorityQueue.popHighest()
    yield candidate
    
    // After execution, if new patterns discovered:
    // They automatically affect next heuristic scores
```

#### Pattern Integration
When new pattern arrives:
1. Update constraint tracking
2. Re-score remaining candidates in priority queue
3. Add new candidates to queue with updated heuristics

**Pros:**
- Dramatically accelerates discovery of high-output programs
- Exploits domain knowledge (jumps → loops → longer execution)
- Gracefully degrades as patterns accumulate
- Can find "best" programs much faster than uniform search
- Combines constraint filtering with intelligent ordering

**Cons:**
- Heuristics are domain-specific and may be wrong
- Requires empirical tuning of heuristic weights
- Priority queue management overhead
- May miss unexpected high-value programs that don't fit heuristics
- More complex to debug (bad heuristic → poor search performance)
- Pattern integration requires re-scoring candidates

**Implementation Sketch:**
```haskell
type HeuristicScore = Double

computeHeuristic :: [Byte] -> [OptimizedProgram] -> HeuristicScore
computeHeuristic candidate patterns =
  let jumpDensity = fromIntegral (length [b | b <- candidate, b `elem` [13,14,15]]) / 
                    fromIntegral (length candidate)
      printCount = fromIntegral (length [b | b <- candidate, b == 8])
      arithmeticCount = fromIntegral (length [b | b <- candidate, b `elem` [1,2,3,4,5,6]])
      matchingConstraints = length $ filter (\p -> matchesPattern candidate p) patterns
      memoryDiversity = fromIntegral $ length $ nub candidate
  in (jumpDensity * 10.0) + (printCount * 20.0) + (arithmeticCount * 5.0) - 
     (fromIntegral matchingConstraints * 3.0) + (memoryDiversity * 2.0)

-- Priority queue based generation
generateHeuristicOrdered :: Int -> [OptimizedProgram] -> [[Byte]]
generateHeuristicOrdered length patterns =
  let candidates = generateNonMatchingCandidates length patterns
      scored = [(computeHeuristic c patterns, c) | c <- candidates]
      sorted = sortBy (comparing (negate . fst)) scored
  in map snd sorted
```

---

### OPTION 5: Incremental Constraint Graph with Adaptive Learning (Cutting-Edge)

**Complexity:** ⭐⭐⭐⭐⭐ Cutting-Edge  
**Chance of Success:** ⭐⭐⭐⭐☆ High (80%)  
**Expected Performance Win:** 20x-100x vs current optimized-search  
**Implementation Effort:** 4-6 weeks  

#### Overview
Maintain a **constraint interaction graph** that tracks which patterns overlap and which regions of the search space are "hot" (high likelihood of interesting programs). Use adaptive learning to refine heuristics based on actual results.

#### How It Works

```
Constraint Interaction Graph:
  Nodes: Each cached pattern
  Edges: Weighted by "overlap degree" (how many programs match both patterns)
  
  Example Graph:
    Pattern_A [8, 15, *] ──(overlap:0.3)─→ Pattern_B [*, 10, *, 4]
    Pattern_A                            /
                    └─ (overlap:0.8) ──┤ Pattern_C [8, *, *, *, 0]
    Pattern_D [*, *, 13, *] ────────────→ Pattern_E [*, *, 13, 5]

  Insights:
  - Patterns A & C overlap heavily (don't explore near them)
  - Pattern D & E overlap heavily (similar space, one is subset of other)
  - Pattern B is isolated (its space may have more unexplored neighbors)

Adaptive Learning:
  For each newly-discovered program with output O:
    - Record: (candidate features, output length)
    - Update heuristic weights: features that led to high O get higher weights
    
  Example:
    [8, 15, 13, 4] → 25 chars output
      Program features:
        - Has PRINT: yes (+1 to print weight)
        - Has JMP: yes (+1 to jump weight)
        - Has Math ops: no (-1 to math weight)
        - Memory coverage: 4 positions (+1 to diversity weight)
      
      Update weights toward high-output features

Generation Strategy:
  1. Compute "frontier" regions: areas not heavily covered by cached patterns
  2. Weight frontier regions higher in heuristic scoring
  3. Apply adaptive heuristic weights from learning
  4. Generate candidates in priority order (frontier first)
  5. Each new result feeds back into learning system
```

#### Pattern Integration
When pattern arrives:
1. Add node to constraint graph
2. Compute overlap edges with existing patterns
3. Identify new frontier regions
4. Update generation heuristics to explore frontiers
5. Adapt weights based on discoveries made near new pattern

**Pros:**
- Most intelligent approach—adapts to search space characteristics
- Can identify "hot" regions and frontier areas automatically
- Learning improves search performance over time
- Gracefully handles sparse vs. dense pattern distributions
- Frontier-guided exploration naturally avoids pattern regions

**Cons:**
- Most complex implementation—requires graph management + learning system
- Overlap computation is expensive (O(P^2) per pattern integration)
- Subtle bugs in graph construction could severely degrade performance
- Learning may converge to local maxima
- Requires significant empirical tuning
- Hard to predict performance on new problem instances

**Implementation Sketch:**
```haskell
data ConstraintGraph = ConstraintGraph
  { patternNodes :: Map.Map Int OptimizedProgram
  , overlapEdges :: Map.Map (Int, Int) Double  -- Overlap degree
  , heuristicWeights :: Map.Map String Double  -- Learned weights
  }

-- Compute overlap between two patterns
computeOverlap :: OptimizedProgram -> OptimizedProgram -> Double
computeOverlap p1 p2 =
  let positions = [0..15]
      matchingPositions = length [pos | pos <- positions, 
                                   wouldMatch (0 :: Byte) p1 pos && 
                                   wouldMatch (0 :: Byte) p2 pos]
  in fromIntegral matchingPositions / 16.0

-- Identify frontier regions (positions with fewer patterns)
identifyFrontier :: ConstraintGraph -> [(Int, Double)]  -- Position, priority
identifyFrontier graph =
  let patternsPerPosition = map (\pos -> 
        (pos, length [p | p <- Map.elems (patternNodes graph), 
                         hasConstraintAtPosition p pos])) [0..15]
  in map (\(pos, count) -> (pos, 1.0 / fromIntegral (count + 1))) patternsPerPosition

-- Adaptive heuristic with learning
computeAdaptiveHeuristic :: [Byte] -> ConstraintGraph -> Double
computeAdaptiveHeuristic candidate graph =
  let baseHeuristics = computeHeuristic candidate (Map.elems $ patternNodes graph)
      learnedFactor = computeFrontierBoost candidate graph
      weightedBase = baseHeuristics * getWeight "base" graph
  in weightedBase + learnedFactor
```

---

## Comparison Matrix

| Aspect | Option 1: Bitmap | Option 2: CSP | Option 3: Inverted Trie | Option 4: Heuristic | Option 5: Adaptive |
|--------|------------------|---------------|------------------------|-------------------|------------------|
| **Complexity** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Success Rate** | 80% | 92% | 85% | 82% | 80% |
| **Perf. Win** | 2-5x | 5-15x | 10-30x | 15-50x | 20-100x |
| **Time to Impl.** | 1-2w | 2-3w | 2-4w | 3-5w | 4-6w |
| **Memory Usage** | Very High | Moderate | Low | Moderate-Low | Low |
| **Pattern Integration** | Simple | Moderate | Simple | Complex | Complex |
| **Heuristic Guidance** | None | None | None | Strong | Very Strong |
| **Debuggability** | Easy | Moderate | Hard | Hard | Very Hard |
| **Risk Level** | Low | Low | Moderate | High | High |

---

## Recommendation

**For immediate implementation**: **OPTION 2 (CSP)** or **OPTION 4 (Heuristic-Guided)**

**Option 2 Reasoning:**
- Strong success rate with moderate complexity
- CSP is mathematically sound—guarantees correctness
- Pattern integration is clean and well-understood
- Can add heuristics as future optimization

**Option 4 Reasoning:**
- Best practical performance win (15-50x)
- Heuristics are intuitive and explainable
- Can empirically tune weights
- Scales well as patterns accumulate

**Avoid initially:**
- **Option 1**: Memory explosion for N>6, limited benefit
- **Option 3**: Complex trie logic, high bug risk
- **Option 5**: Overkill for current problem scale, too risky

**Suggested Path:**
1. Implement **Option 4** first (heuristic-guided)
2. If time permits, add **Option 5** learning layer
3. Keep **Option 1** as fallback if complexity issues arise

---

## Expected Results

Once implemented, expect:

### For Length 6 Programs (16M total):
- **Current optimized-search**: ~1-2 hours runtime
- **Option 2 (CSP)**: ~10-15 minutes (8-12x improvement)
- **Option 4 (Heuristic)**: ~5-10 minutes (12-20x improvement)
- **Option 5 (Adaptive)**: ~3-5 minutes (20-40x improvement)

### For Length 7 Programs (268M total):
- **Current optimized-search**: ~30-60 hours (infeasible)
- **Option 2 (CSP)**: ~3-5 hours (60-100x improvement)
- **Option 4 (Heuristic)**: ~1-3 hours (100-300x improvement)
- **Option 5 (Adaptive)**: ~30-90 minutes (200-400x improvement)

### For Length 8 Programs (4.3B total):
- **Current optimized-search**: Not practical
- **Option 2 (CSP)**: ~48-96 hours (marginal)
- **Option 4 (Heuristic)**: ~12-24 hours (practical with patience)
- **Option 5 (Adaptive)**: ~4-8 hours (practical)

---

## Next Steps

Please select one of the five approaches for implementation. I recommend:

1. **Choose approach** based on your preferred balance of speed vs. complexity
2. **Specify heuristics** (for Options 4 & 5) based on domain insights
3. **Define success criteria** (performance improvement targets)
4. **Set up testing framework** to validate against current optimized-search results

The new command will coexist with the current `optimized-search` command, allowing A/B comparison of performance.
