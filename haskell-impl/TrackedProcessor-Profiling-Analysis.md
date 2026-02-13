# TrackedProcessor Profiling Analysis

## Profile Data: optimized-search --length 3

**Total runtime**: 0.12 seconds (119 ticks @ 1000 us)  
**Total allocation**: 565,990,968 bytes (~566 MB)

## Critical Finding: TrackedProcessor is NOT the Bottleneck! 🎯

### Top Functions by Time & Allocation:

1. **matchesPattern** (WildcardPattern.hs)
   - **%time: 42.9%** ⚠️ HOTTEST
   - **%alloc: 51.4%** ⚠️ LARGEST ALLOCATOR
   - Lines: 353-361
   - **This is the wildcard pattern matching logic, NOT TrackedProcessor**

2. **matchesByte** (WildcardPattern.hs)
   - **%time: 23.5%** (2nd hottest)
   - **%alloc: 0.0%** (no allocation)
   - Lines: 365-368
   - Helper function for pattern matching

3. **lookupPattern.storedPrograms** (WildcardCache.Trie.hs)
   - **%time: 7.6%**
   - **%alloc: 13.2%**
   - Cache trie lookup

4. **lookupPattern.matchingProgram** (WildcardCache.Trie.hs)
   - **%time: 5.0%**
   - **%alloc: 0.0%**
   - Pattern matching in cache

5. **matchesPattern.paddedProgram** (WildcardPattern.hs)
   - **%time: 4.2%**
   - **%alloc: 15.2%**
   - Program padding for pattern matching

## Key Insights:

### 1. **The Real Bottleneck: Wildcard Pattern Matching** 🔥
- **66.4% of execution time** is spent on `matchesPattern` and `matchesByte`
- **66.6% of memory allocation** is in pattern matching and padding
- This is NOT TrackedProcessor overhead at all!

### 2. **Cache Operations are Relatively Cheap**
- Total cache operations: ~12.6% of time
- The caching system is working well

### 3. **TrackedProcessor Not Visible in Top Costs**
- TrackedProcessor functions don't appear in the top cost centers
- This suggests TrackedProcessor overhead is <5% of total time
- The 2.57x slowdown in benchmarks is NOT the concern for integrated search

### 4. **Memory Allocation is the Bigger Issue Than Time**
- 565 MB allocated for ~4000 program evaluations
- Pattern matching is allocating heavily (51.4% of total)
- The padding and pattern creation is generating lots of temporary objects

## Recommendations: Wrong Target

❌ **DO NOT optimize TrackedProcessor** - it's not the bottleneck in optimized-search!

✅ **Instead, optimize the Wildcard Pattern Matching:**

### High-Impact Optimizations:

1. **Reduce Pattern Padding Allocations** (Likely 15-20% improvement)
   - `matchesPattern.paddedProgram` allocates 15.2% of memory
   - Avoid creating padded copies, pad lazily or in-place
   - Code location: WildcardPattern.hs:355

2. **Optimize matchesByte** (Likely 10-15% improvement)
   - This is called frequently and is 2nd hottest
   - Profile shows it allocates nothing but takes 23.5% of time
   - Look for:
     - Unboxed comparisons
     - Reduce pattern matching overhead
     - Inline critical paths

3. **Cache More Aggressively** (Likely 5-10% improvement)
   - Only 74.2% cache hit rate for length 3
   - Improve pattern matching to catch more equivalences
   - Better trie structure for faster lookups

4. **Reduce Pattern Matching Complexity** (Likely 10-20% improvement)
   - The `matchesPattern` function is doing 42.9% of all work
   - Split into simpler cases
   - Use specialized fast-paths for common patterns

## Historical Context: Why the 2.57x Benchmark Slowdown?

The 2.57x slowdown between Processor and TrackedProcessor in benchmarks is real, but:

1. **Not relevant** to this profile - `optimized-search` uses wildcard caching
2. **The benchmark** runs very small programs repeatedly in isolation
3. **In benchmarks**, TrackedProcessor overhead is more visible (small per-program costs)
4. **In actual search**, cache and pattern matching dominate overall time

The TrackedProcessor overhead (detailed tracking) is real (~2.57x per-step), but it's not the bottleneck in the overall search pipeline because:
- Caching skips 74.2% of executions
- Pattern matching preprocessing dominates the work
- Only 25.8% of programs actually run through TrackedProcessor

## Conclusion:

**The profiling reveals we've been looking at the wrong target.**

The TrackedProcessor itself isn't causing the performance issues in `optimized-search`. The real work is:
1. **Wildcard pattern matching** (66% of time)
2. **Memory allocation** in pattern processing (51% of allocations)
3. **Cache lookups** (13% of time)

### Two Different Optimization Targets:

#### If optimizing `optimized-search` performance:
→ Focus on reducing pattern matching costs (this profile)

#### If optimizing TrackedProcessor for standalone use:
→ The Map/Set operations ARE still valid targets (benchmark data)
→ But they won't impact the integrated search pipeline significantly

## Next Steps:

1. Profile `matchesPattern` function in detail
2. Analyze memory allocation patterns in WildcardPattern.hs
3. Consider alternative pattern matching algorithms
4. Add strictness annotations to reduce lazy evaluation overhead
