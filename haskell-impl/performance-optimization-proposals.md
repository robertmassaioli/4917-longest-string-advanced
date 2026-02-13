# Performance Optimization Proposals for optimized-search

**Created**: 2026-02-13 09:55:39 UTC  
**Git Hash**: 8a8a08e3b7318917264bd14affd24d820d86c83c  
**Branch**: feature/usage-aware-optimization-display

## Context

Based on GHC profiling of `optimized-search --length 3`:
- **Total runtime**: 0.12 seconds (119 ticks)
- **Total allocation**: 565,990,968 bytes (~566 MB)
- **Top bottleneck**: Pattern matching (66.4% of time, 66.6% of allocations)
- **Cache hit rate**: 74.2%

### Current Performance Profile
```
matchesPattern:              42.9% time, 51.4% alloc
matchesByte:                 23.5% time,  0.0% alloc
lookupPattern.storedPrograms: 7.6% time, 13.2% alloc
lookupPattern.matchingProgram: 5.0% time,  0.0% alloc
matchesPattern.paddedProgram:  4.2% time, 15.2% alloc
matchesPattern.paddedPattern:  3.4% time, 15.3% alloc
```

## Summary of Proposals

This document presents **8 concrete optimization proposals** based on profiling analysis.

**Key Finding**: Pattern matching (`matchesPattern` + `matchesByte`) accounts for **66.4% of total runtime** and is the primary bottleneck.

### Recommended Implementation Order

**🔴 Tier 1 - Top Priority (Must Do First)**
1. **Bitmap-Based Pattern Matching** ⭐ - 30-40% improvement (User proposal, addresses 66.4% bottleneck)
2. **Eliminate Pattern Padding** - 15-25% improvement (Quick win, complements #1)

**🟡 Tier 2 - Medium Priority**
3. **Optimize matchesByte Function** - 10-20% improvement (Alternative to #1 if bitmap fails)
4. **Lazy Cache Lookup** - 5-10% improvement (Easy optimization)
5. **Specialize matchesPattern** - 20-35% improvement (More complex, multi-tier approach)

**🟢 Tier 3 - Advanced/Future**
6. **Vector Representation** - 15-30% improvement (Pervasive change, high effort)
7. **Compiled Decision Trees** - 30-50% improvement (Research-level complexity)
8. **Parallelization** - 2-4x improvement (Orthogonal, requires multi-core)

**Combined Potential**: Implementing #1 + #2 could yield **40-55% total improvement**.

---

## Proposal #1: Bitmap-Based Pattern Matching ⭐ **USER PROPOSAL**

**Likelihood of Working**: 85-90%  
**Expected Performance Gain**: 30-40%  
**Implementation Effort**: Medium (4-5 hours)  
**Risk Level**: Low  
**Priority**: 🔴 **RANK #1 - STRONGLY RECOMMENDED**

### Problem Statement

Current pattern matching uses:
- `Required Byte`: Simple equality check (fast)
- `Wildcard`: Always true (fastest)
- `AnyOf [Byte]`: List membership check with `elem` (slow!)

The `matchesByte` function performs 16 pattern matches per program, accounting for **23.5% of total runtime**. The `AnyOf` case uses `elem` which is O(n) and causes branching overhead.

**Profiling shows**: Pattern matching is **66.4% of total runtime** - our #1 bottleneck.

### Solution

Convert `OptimizedInstruction` patterns to bitmap representation:

```haskell
-- Each instruction becomes a 16-bit mask (one bit per possible byte value 0-15)
type InstructionMask = Word16
type BitmapPattern = Vector InstructionMask

-- Examples:
-- Required 5:     0000000000100000  (only bit 5 set)
-- Wildcard:       1111111111111111  (all bits set)
-- AnyOf [1,2,9]:  0000001000000110  (bits 1,2,9 set)

-- Ultra-fast matching using bitwise AND
matchesBitmapPattern :: [Byte] -> BitmapPattern -> Bool
matchesBitmapPattern program pattern =
    let programMasks = Vector.map (1 `shiftL` . fromIntegral) (Vector.take 16 $ Vector.fromList (program ++ repeat 0))
    in Vector.all id $ Vector.zipWith (\p m -> (p .&. m) == p) programMasks pattern
```

### Why This Works

1. **Eliminates List Operations**: `elem` on lists is O(n) - replace with O(1) bitwise AND
2. **Eliminates Branching**: Single AND operation instead of case statement + list traversal
3. **Better CPU Performance**: Bit operations are among the fastest CPU instructions
4. **Compact Representation**: 16 Word16 values = 32 bytes (vs ~200+ bytes with constructors)
5. **Cache Friendly**: Tight memory layout, better cache locality
6. **Vectorizable**: Modern CPUs can parallelize bitwise operations

### Implementation Steps

**Phase 1: Core Implementation (1-2 hours)**
- Add `InstructionMask` and `BitmapPattern` types
- Implement `toBitmapPattern` conversion function
- Implement `matchesBitmapPattern` with INLINE pragmas

**Phase 2: Integration (1 hour)**
- Add `bitmapPattern :: Maybe BitmapPattern` to `OptimizedProgram`
- Lazy initialization on first use
- Cache result for repeated matches

**Phase 3: Optimization (30 mins)**
- Add strictness annotations
- Use unboxed Vector operations
- Inline hot path functions

**Phase 4: Testing & Validation (1 hour)**
- Unit tests for conversion correctness
- Edge case testing (empty programs, all wildcards, all required)
- Profile on actual workload

### Success Criteria

✅ All existing tests pass  
✅ Bitmap matching identical to original implementation  
✅ **20% minimum improvement** (acceptable)  
✅ **30-40% target improvement** (expected)  
✅ **45%+ stretch goal** (optimistic)  
✅ `matchesByte` drops from 23.5% to <10% of runtime  
✅ No new bottlenecks introduced  

### Risks & Mitigation

| Risk | Probability | Mitigation |
|------|-------------|-----------|
| Conversion overhead dominates | 15-20% | Profile implementation, use lazy conversion |
| CPU doesn't optimize bitops | 10-15% | Still faster than list operations |
| Cache misses increase | 10% | Memory layout is actually more compact |

**Overall Risk**: LOW

### Why This Ranks #1

1. ✅ **Directly addresses 66.4% of bottleneck** (pattern matching)
2. ✅ **Straightforward implementation** - no complex algorithms
3. ✅ **Easy to validate** - correctness is deterministic
4. ✅ **Low risk** - can rollback if needed
5. ✅ **Complementary** - works with other optimizations
6. ✅ **User validated** - identified through profiling analysis

---

## Proposal #2: Eliminate Pattern Padding Allocations  
**Expected Improvement**: 15-25% overall performance, 30% less memory

### Problem
The `matchesPattern` function pads both programs and patterns to compare them:
```haskell
-- Current implementation (WildcardPattern.hs:355-360)
matchesPattern :: OptimizedProgram -> [Byte] -> Bool
matchesPattern optProg program = 
    let pattern = wildcardPattern optProg
        paddedProgram = program ++ replicate (16 - length program) 0
        -- ...
        paddedPattern = pattern ++ replicate (16 - length pattern) Wildcard
```

This creates two new lists on every comparison, causing 30.5% of all allocations.

### Solution
Use indexed comparison without creating padded copies:

```haskell
matchesPattern :: OptimizedProgram -> [Byte] -> Bool
matchesPattern optProg program = 
    let pattern = wildcardPattern optProg
        maxLen = max (length program) (length pattern)
    in all (\i -> matchesByteAt i program pattern) [0..maxLen-1]

matchesByteAt :: Int -> [Byte] -> [OptimizedInstruction] -> Bool
matchesByteAt i program pattern =
    let progByte = if i < length program then program !! i else 0
        patByte = if i < length pattern then pattern !! i else Wildcard
    in matchesByte progByte patByte
```

### Implementation Strategy
1. Refactor `matchesPattern` to use indexed access
2. Add specialized fast-path for equal-length comparisons
3. Benchmark with profiling enabled
4. Verify correctness with existing test suite

### Success Criteria
- Reduce allocations by at least 25%
- Improve runtime by at least 15%
- All tests pass
- Cache hit rate remains >= 74%

---

## Proposal #3: Optimize matchesByte with Unboxed Comparisons

**Target**: `matchesByte` function  
**Current Cost**: 23.5% time, 0% allocations  
**Expected Improvement**: 10-20% overall performance

### Problem
`matchesByte` is the second hottest function but allocates nothing, suggesting it's spending time on pattern matching overhead and function call costs:

```haskell
-- Current implementation (WildcardPattern.hs:365-368)
matchesByte :: Byte -> OptimizedInstruction -> Bool
matchesByte _ Wildcard = True
matchesByte b (Required req) = b == req
matchesByte b (AnyOf options) = b `elem` options
```

The `elem` lookup for `AnyOf` is O(n) on a list, and the pattern matching has overhead.

### Solution A: Use Unboxed Word16 Bitmask for AnyOf
```haskell
data OptimizedInstruction 
    = Wildcard
    | Required !Byte
    | AnyOfMask !Word16  -- Bitmask where bit i = value i is allowed

matchesByte :: Byte -> OptimizedInstruction -> Bool
matchesByte _ Wildcard = True
matchesByte b (Required req) = b == req
matchesByte b (AnyOfMask mask) = testBit mask (fromIntegral b)
```

### Solution B: Use INLINE and Strict Pattern Matching
```haskell
{-# INLINE matchesByte #-}
matchesByte :: Byte -> OptimizedInstruction -> Bool
matchesByte !b !instr = case instr of
    Wildcard -> True
    Required !req -> b == req
    AnyOf !options -> b `elem` options  -- or use Set lookup
```

### Solution C: Combine Both
Use bitmask representation + INLINE + strict evaluation.

### Implementation Strategy
1. Change internal representation of `AnyOf` to use `Word16` bitmask
2. Add conversion functions to/from list representation for JSON/display
3. Add `{-# INLINE matchesByte #-}` pragma
4. Use strict pattern matching and bangs
5. Profile to measure improvement

### Success Criteria
- Reduce `matchesByte` time from 23.5% to < 15%
- Improve overall runtime by 10-15%
- Maintain correctness
- No significant allocation increase

---

## Proposal #4: Use Vector Instead of Lists for Programs

**Target**: All program representations  
**Current Cost**: Indirect (list traversal overhead throughout)  
**Expected Improvement**: 15-30% overall performance

### Problem
Programs are represented as `[Byte]` lists, which have:
- O(n) indexing cost
- Poor cache locality
- Allocation overhead for cons cells
- No fusion opportunities

The pattern matching code frequently indexes into programs:
```haskell
program !! i  -- O(n) for lists
```

### Solution
Use `Vector Byte` (unboxed) for all program representations:

```haskell
type Program = Vector Byte  -- Unboxed vector

-- Benefits:
-- - O(1) indexing
-- - Compact memory representation (no cons cells)
-- - Better cache locality
-- - GHC fusion for vector operations
```

### Changes Required
1. Update `OptimizedProgram` to use `Vector Byte`
2. Update `matchesPattern` to use vector operations
3. Update cache structures to work with vectors
4. Update JSON serialization/deserialization
5. Update all client code

### Implementation Strategy
1. Create type alias: `type Program = Vector Byte`
2. Convert list-based code module by module
3. Use `Vector.!` for O(1) indexing
4. Leverage vector fusion for comparisons
5. Profile each module conversion

### Success Criteria
- Reduce overall time by 15-25%
- Reduce memory allocations by 20-30%
- Maintain or improve cache hit rate
- All tests pass after conversion

### Risk Assessment
**High risk** - Pervasive change affecting many modules  
**Mitigation**: Implement incrementally, test after each module

---

## Proposal #5: Implement Lazy/Memoized Pattern Cache Lookup

**Target**: `lookupPattern` in Trie cache  
**Current Cost**: 12.6% time, 13.2% allocations  
**Expected Improvement**: 5-10% overall performance

### Problem
The trie lookup creates intermediate data structures during traversal:
```haskell
lookupPattern.storedPrograms: 7.6% time, 13.2% alloc
lookupPattern.matchingProgram: 5.0% time, 0.0% alloc
```

### Solution A: Use Strict Evaluation for Trie Nodes
```haskell
data TrieNode = TrieNode
    { nodePatterns :: !(Set Int)  -- Strict fields
    , nodeEdges :: !(Map Byte TrieNode)  -- Strict Map
    , wildcardEdge :: !(Maybe TrieNode)  -- Strict Maybe
    }
```

### Solution B: Implement Bloom Filter Pre-Check
```haskell
data TrieNode = TrieNode
    { nodeBloomFilter :: !Word64  -- Quick negative check
    , nodePatterns :: !(Set Int)
    , nodeEdges :: !(Map Byte TrieNode)
    }

lookupPattern :: [Byte] -> TrieNode -> Maybe OptimizedProgram
lookupPattern program node =
    if not (bloomCheck program (nodeBloomFilter node))
    then Nothing  -- Fast path: definitely not in this subtree
    else -- Continue with full lookup
```

### Solution C: Use IntMap Instead of Map for Edges
```haskell
data TrieNode = TrieNode
    { nodePatterns :: !(IntSet)  -- IntSet instead of Set Int
    , nodeEdges :: !(IntMap TrieNode)  -- IntMap instead of Map Byte
    }
```

### Implementation Strategy
1. Add strictness annotations to TrieNode
2. Replace Map/Set with IntMap/IntSet
3. Optionally add bloom filter for negative checks
4. Profile each change independently
5. Keep the best combination

### Success Criteria
- Reduce lookup time from 12.6% to < 8%
- Reduce lookup allocations by 50%
- Maintain or improve cache functionality

---

## Proposal #6: Specialize matchesPattern for Common Cases

**Target**: `matchesPattern` function  
**Current Cost**: 42.9% time, 51.4% allocations  
**Expected Improvement**: 20-35% overall performance

### Problem
`matchesPattern` is a one-size-fits-all function that handles all pattern types equally. Most patterns are simple and could use fast-paths.

### Solution: Multi-tier matching with fast-paths

```haskell
-- Fast path 1: No wildcards (exact match)
matchesPatternExact :: [Byte] -> [Byte] -> Bool
matchesPatternExact program pattern = program == pattern

-- Fast path 2: Only trailing wildcards
matchesPatternPrefix :: [Byte] -> [Byte] -> Bool
matchesPatternPrefix program pattern = 
    take (length pattern) program == pattern

-- Fast path 3: Single AnyOf instruction
matchesPatternSingleChoice :: [Byte] -> [Byte] -> Int -> [Byte] -> Bool
-- ... specialized implementation

-- General case: Full wildcard matching
matchesPatternGeneral :: OptimizedProgram -> [Byte] -> Bool
-- ... current implementation

-- Dispatcher
matchesPattern :: OptimizedProgram -> [Byte] -> Bool
matchesPattern optProg program =
    case analyzePatternComplexity (wildcardPattern optProg) of
        ExactMatch -> matchesPatternExact program (originalProgram optProg)
        PrefixMatch prefix -> matchesPatternPrefix program prefix
        SingleChoice pos opts -> matchesPatternSingleChoice program ...
        Complex -> matchesPatternGeneral optProg program
```

### Pattern Complexity Analysis
```haskell
data PatternComplexity 
    = ExactMatch
    | PrefixMatch [Byte]
    | SingleChoice Int [Byte]
    | FewChoices [(Int, [Byte])]
    | Complex

analyzePatternComplexity :: [OptimizedInstruction] -> PatternComplexity
analyzePatternComplexity pattern = 
    -- Analyze pattern structure and choose best fast-path
```

### Implementation Strategy
1. Add pattern complexity analysis during cache insertion
2. Store complexity with OptimizedProgram
3. Implement specialized matchers for each tier
4. Add dispatcher that selects appropriate matcher
5. Profile to verify each fast-path helps

### Success Criteria
- Reduce `matchesPattern` time from 42.9% to < 25%
- Reduce overall allocations by 30-40%
- Maintain correctness for all pattern types
- Cache hit rate remains >= 74%

---

## Proposal #7: Implement Parallel Pattern Matching

**Target**: Overall search pipeline  
**Current Cost**: Entire 0.12s runtime  
**Expected Improvement**: 2-4x on multi-core systems

### Problem
Current implementation is single-threaded. The search evaluates 4096 programs but only uses one core.

### Solution: Parallel map over program candidates

```haskell
import Control.Parallel.Strategies (parMap, rdeepseq)

optimizedSearch :: Int -> IO ()
optimizedSearch len = do
    let programs = allProgramsOfLength len
        chunks = chunksOf 256 programs  -- Chunk size tuned for cache
    
    results <- mapM (evaluateChunk cache) chunks `using` parList rdeepseq
    -- Process results...

evaluateChunk :: Cache -> [Program] -> [(Program, Int)]
evaluateChunk cache programs = 
    map (\p -> (p, evaluateWithCache cache p)) programs
```

### Challenges
1. **Cache sharing** - Need thread-safe cache or per-thread caches
2. **Load balancing** - Cached programs finish instantly vs. uncached are slow
3. **Memory usage** - Parallel execution increases memory pressure

### Solution A: Thread-Local Caches + Merge
```haskell
-- Each thread maintains its own cache
-- Merge caches at the end
```

### Solution B: Concurrent Cache with STM
```haskell
import Control.Concurrent.STM

type ConcurrentCache = TVar (Map Pattern OptimizedProgram)

lookupConcurrent :: ConcurrentCache -> Pattern -> STM (Maybe OptimizedProgram)
insertConcurrent :: ConcurrentCache -> Pattern -> OptimizedProgram -> STM ()
```

### Implementation Strategy
1. Start with simple `parMap` over program list
2. Measure speedup and identify contention
3. Implement thread-local caches if needed
4. Tune chunk size for best throughput
5. Profile to ensure no regression in cache hit rate

### Success Criteria
- 2-4x speedup on 4+ core systems
- Linear scaling up to 4-8 cores
- Cache hit rate remains >= 70%
- No deadlocks or race conditions

### Risk Assessment
**Medium risk** - Concurrency adds complexity  
**Mitigation**: Start simple, add complexity only if needed

---

## Proposal #8: Pre-compile Pattern Matching to Decision Trees

**Target**: `matchesPattern` and `matchesByte`  
**Current Cost**: 66.4% time combined  
**Expected Improvement**: 30-50% overall performance

### Problem
Pattern matching interprets patterns at runtime. For frequently-used patterns, we could compile them to optimized decision trees.

### Solution: Pattern Compilation

```haskell
-- Compiled pattern representation
data CompiledPattern 
    = CPExact ![Byte]
    | CPPrefixWildcard ![Byte]  -- Prefix followed by wildcards
    | CPDecisionTree !(DecisionTree Byte Bool)

data DecisionTree a b
    = Leaf b
    | Branch Int [(a, DecisionTree a b)] (DecisionTree a b)
    -- Branch position [(value, subtree)] defaultSubtree

-- Compilation
compilePattern :: [OptimizedInstruction] -> CompiledPattern
compilePattern pattern = 
    case analyzePattern pattern of
        AllRequired bytes -> CPExact bytes
        PrefixRequired prefix -> CPPrefixWildcard prefix
        Complex -> CPDecisionTree (buildDecisionTree pattern)

-- Fast matching
matchesCompiled :: CompiledPattern -> [Byte] -> Bool
matchesCompiled (CPExact bytes) program = program == bytes
matchesCompiled (CPPrefixWildcard prefix) program = 
    take (length prefix) program == prefix
matchesCompiled (CPDecisionTree tree) program = 
    evaluateTree tree program

evaluateTree :: DecisionTree Byte Bool -> [Byte] -> Bool
evaluateTree (Leaf result) _ = result
evaluateTree (Branch pos choices default_) program =
    case lookup (program !! pos) choices of
        Just subtree -> evaluateTree subtree program
        Nothing -> evaluateTree default_ program
```

### Decision Tree Optimization
- Optimal branching order (highest entropy first)
- Merge equivalent subtrees
- Eliminate redundant checks

### Implementation Strategy
1. Implement pattern analysis and classification
2. Build decision tree compiler
3. Add compiled pattern to cache entries
4. Update matching to use compiled patterns
5. Profile to verify improvement

### Success Criteria
- Reduce pattern matching time by 40-60%
- Maintain correctness
- Compilation overhead < 1% of total time
- Cache hit rate unaffected

---

## Implementation Recommendations

### Recommended Order (Risk vs. Reward)

1. **Start with Proposal 1** (Eliminate padding allocations)
   - **Effort**: Low
   - **Risk**: Low
   - **Reward**: High (15-25% improvement)
   - **Branch**: `optimize/eliminate-padding`

2. **Then Proposal 2** (Optimize matchesByte)
   - **Effort**: Low
   - **Risk**: Low
   - **Reward**: Medium (10-20% improvement)
   - **Branch**: `optimize/matchbyte-unboxed`

3. **Then Proposal 5** (Specialize matchesPattern)
   - **Effort**: Medium
   - **Risk**: Medium
   - **Reward**: High (20-35% improvement)
   - **Branch**: `optimize/pattern-fastpaths`

4. **Then Proposal 4** (Lazy cache lookup)
   - **Effort**: Low
   - **Risk**: Low
   - **Reward**: Low-Medium (5-10% improvement)
   - **Branch**: `optimize/strict-cache`

5. **Then Proposal 3** (Vector representation)
   - **Effort**: High
   - **Risk**: High
   - **Reward**: High (15-30% improvement)
   - **Branch**: `optimize/vector-programs`

6. **Consider Proposal 6** (Parallelization) if sequential optimizations aren't enough
   - **Effort**: Medium
   - **Risk**: Medium
   - **Reward**: Very High (2-4x on multi-core)
   - **Branch**: `optimize/parallel-search`

7. **Advanced: Proposal 7** (Compiled patterns) for maximum performance
   - **Effort**: High
   - **Risk**: Medium
   - **Reward**: Very High (30-50% improvement)
   - **Branch**: `optimize/compiled-patterns`

### Testing Strategy for Each Proposal

1. **Create feature branch** from current state
2. **Implement optimization** with minimal changes
3. **Run profiling**: `stack exec --profile -- 4917-cli optimized-search --length 3 +RTS -p -RTS`
4. **Compare results**:
   - Runtime improvement
   - Allocation reduction
   - Profile cost center changes
5. **Run test suite**: `stack test`
6. **Run benchmarks**: `stack bench :trackedprocessor-bench`
7. **Document results** in branch
8. **If successful**: Merge to main
9. **If not**: Archive branch, document learnings

### Combined Impact Estimate

If all successful optimizations are merged:
- **Conservative estimate**: 50-70% faster, 40-60% less memory
- **Optimistic estimate**: 70-85% faster, 60-75% less memory
- **With parallelization**: 3-6x faster on 8-core systems

### Success Metrics

Track these metrics for each optimization:
- **Runtime** (should decrease)
- **Memory allocations** (should decrease)
- **Cache hit rate** (should stay >= 70%)
- **Test pass rate** (must remain 100%)
- **Top cost centers** (should shift away from optimized functions)

---

## Conclusion

Based on profiling data, we have 7 concrete optimization proposals targeting the real bottlenecks:
1. Pattern matching (66.4% of time)
2. Memory allocation (566 MB for 4K programs)
3. Cache lookup overhead (12.6% of time)

Each proposal includes:
- ✅ Clear problem statement with profiling data
- ✅ Concrete solution with code examples
- ✅ Implementation strategy
- ✅ Success criteria
- ✅ Risk assessment

**Next steps**: Implement proposals one at a time, profile each, and merge the winners.

---

**Document Status**: Ready for review and implementation  
**Expected timeline**: 1-2 weeks for proposals 1-5, 2-3 weeks if including 6-7
