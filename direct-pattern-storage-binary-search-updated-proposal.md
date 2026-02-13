# Direct Pattern Storage with Binary Search - Updated Implementation Proposal

**Status**: Implementation-ready proposal based on current codebase state (Feb 2026)

**Scope**: Implement Option 2 from `optimized-program-lookup-cache-proposal.md` tailored to the current WildcardCache architecture

---

## Executive Summary

This proposal outlines the implementation of **Direct Pattern Storage with Binary Search** as a new cache backend for the 4917 project. The design leverages the existing **bitmap-based pattern matching** infrastructure (already implemented in `WildcardPattern.hs`) and adds efficient storage, retrieval, and persistence mechanisms.

### Key Advantages Over Current Trie Implementation

| Aspect | Current Trie | Proposed Vector + Binary Search |
|--------|--------------|--------------------------------|
| **Lookup Performance** | O(L) with tree traversal overhead | O(P) linear scan or O(log P + L) with binary search |
| **Memory Layout** | Tree structure with pointers | Contiguous vector (cache-friendly) |
| **Implementation Complexity** | Complex (multiple edge types) | Simple (just vectors and pattern matching) |
| **Persistence** | Working but requires careful serialization | Natural vector serialization |
| **Pattern Matching** | Partially working, currently uses linear scan | Uses proven bitmap matching from WildcardPattern |

---

## Current State Analysis

### Existing Infrastructure

#### 1. **Bitmap-Based Pattern Matching** (`WildcardPattern.hs`)
- **Core Type**: `BitmapPattern = BVector.Vector InstructionMask`
- **Storage**: 16 masks (one per memory position), each `Word16` (32 bits for 16 byte values)
- **Matching**: `matchesBitmapPattern :: [Byte] -> BitmapPattern -> Bool`
  - Uses bitwise AND for O(1) per-position matching
  - No list allocations, highly optimized
  - Already proven fast and correct

```haskell
-- Fast bitwise matching already implemented
matchesBitmapPattern :: [Byte] -> BitmapPattern -> Bool
matchesBitmapPattern rawProgram bitmask =
    let len = min 16 (length rawProgram)
        programMasks = BVector.create $ do
            v <- MVector.replicate 16 0
            forM_ [0..len-1] $ \i ->
                MVector.write v i (1 `shiftL` fromIntegral (rawProgram !! i))
            return v
        matchPositions = BVector.zipWith (\p m -> (p .&. m) == p) programMasks bitmask
    in BVector.all id matchPositions
```

#### 2. **Type System** (`WildcardCache/Types.hs`)
- `WildcardPatternCache` typeclass: defines `lookupPattern`, `insertPattern`, `emptyCache`, `getCacheStats`
- `PersistentCache` typeclass: defines `saveCache`, `loadCache`, `appendToCache`
- `CacheStats`: tracks patterns, lookups, hits, misses, avg time, memory
- `CacheConfig`: max patterns, stats tracking, persistence file

#### 3. **Current Trie Implementation** (`WildcardCache/Trie.hs`)
- Uses `matchesPattern` function for linear search (fallback, working)
- Trie structure defined but **lookup currently uses linear scan**
- Shows that pattern matching is the bottleneck, not the structure

#### 4. **OptimizedProgram Structure** (`WildcardPattern.hs`)
- Primary storage: `wildcardPatternBitmask :: BitmapPattern` (16 Word16s)
- Metadata: original program, reduction factor, equivalence class, analysis
- Human-readable: `wildcardPattern :: OptimizedProgram -> [OptimizedInstruction]` (on-demand conversion)

---

## Proposed Architecture

### Data Structures

#### 1. **Vector-Based Pattern Index**

```haskell
-- | Direct pattern storage with efficient lookup
data VectorPatternCache = VectorPatternCache
    { sortedPatterns :: Vector.Vector (BitmapPattern, OptimizedProgram)  -- Sorted patterns
    , patternCount :: Int                                                 -- Number of cached patterns
    , cacheStats :: CacheStats                                           -- Performance metrics
    , config :: CacheConfig                                              -- Configuration
    , lastModified :: Maybe UTCTime                                      -- Persistence timestamp
    } deriving (Show)
```

**Design Rationale**:
- **Vector.Vector**: Contiguous memory layout for cache efficiency
- **BitmapPattern first**: Enables fast pattern matching without dereferencing OptimizedProgram
- **Sorted order**: Enables binary search optimization when patterns accumulate
- **Separate stats**: Tracks cache effectiveness for monitoring

#### 2. **Comparison Function for Sorting**

```haskell
-- | Compare patterns for sorting (enables binary search optimization)
-- Ordering: by pattern "specificity" - more Required bytes come first
comparePatterns :: BitmapPattern -> BitmapPattern -> Ordering
comparePatterns pat1 pat2 =
    let specificity1 = countRequiredPositions pat1  -- How "constrained" is this pattern?
        specificity2 = countRequiredPositions pat2
    in case compare specificity2 specificity1 of    -- More specific patterns first
        EQ -> compare (BVector.toList pat1) (BVector.toList pat2)  -- Tiebreaker
        other -> other

-- | Count positions that are Required (single bit set) vs Wildcard
countRequiredPositions :: BitmapPattern -> Int
countRequiredPositions = BVector.length . BVector.filter isSingleBit . id
  where
    isSingleBit mask = popCount mask == 1
```

**Rationale**: More specific patterns should be checked first for better cache locality and early termination in the linear scan.

---

## Implementation Components

### 1. **Core Lookup Implementation**

#### Linear Scan (For Small Cache Sizes)

```haskell
-- | Linear scan through patterns (efficient for < 1000 patterns)
linearScanLookup :: [Byte] -> VectorPatternCache -> Maybe OptimizedProgram
linearScanLookup program cache = 
    Vector.find (matchesBitmapPattern program . fst) (sortedPatterns cache)
    >>= return . snd

instance WildcardPatternCache VectorPatternCache where
    lookupPattern program cache = 
        if patternCount cache < 1000
            then linearScanLookup program cache
            else binarySearchLookup program cache
    
    insertPattern optProg cache = 
        let bitmask = wildcardPatternBitmask optProg
            newPatterns = Vector.snoc (sortedPatterns cache) (bitmask, optProg)
            -- Maintain sorted order by specificity
            sortedNew = Vector.modify (sortBySpecificity) newPatterns
            updatedStats = (cacheStats cache) 
                { totalPatterns = patternCount cache + 1 }
        in cache
            { sortedPatterns = sortedNew
            , patternCount = patternCount cache + 1
            , cacheStats = updatedStats
            }
```

#### Binary Search Optimization (For Large Cache Sizes)

```haskell
-- | Binary search optimization for large caches
-- Note: Binary search requires ordered patterns that enable early termination
binarySearchLookup :: [Byte] -> VectorPatternCache -> Maybe OptimizedProgram
binarySearchLookup program cache = 
    -- Binary search finds a candidate range, then linear search within that range
    let patterns = sortedPatterns cache
        len = Vector.length patterns
        
        -- Heuristic: patterns with similar specificity may match
        programSpecificity = analyzeRawProgramSpecificity program
        
        -- Find range of patterns with similar specificity
        (startIdx, endIdx) = findSimilarSpecificityRange programSpecificity patterns
        
        -- Linear search within the promising range
        rangePatterns = Vector.slice startIdx (endIdx - startIdx) patterns
    in Vector.find (matchesBitmapPattern program . fst) rangePatterns
       >>= return . snd

-- | Analyze specificity of raw program for binary search hints
analyzeRawProgramSpecificity :: [Byte] -> (Int, Int)
analyzeRawProgramSpecificity program =
    let constraintCount = length program  -- Programs with data are more constrained
    in (constraintCount, 0)  -- Simple heuristic: program length

-- | Find range of patterns matching program's specificity
findSimilarSpecificityRange :: (Int, Int) -> Vector.Vector (BitmapPattern, OptimizedProgram) -> (Int, Int)
findSimilarSpecificityRange spec patterns =
    let len = Vector.length patterns
        specificities = Vector.map (countRequiredPositions . fst) patterns
        
        -- Find range where specificity matches program
        start = Vector.findIndex (\s -> s <= fst spec + 2) specificities
        end = Vector.findIndex (\s -> s >= fst spec - 2) specificities
    in case (start, end) of
        (Just s, Just e) -> (s, min (e + 1) len)
        (Just s, Nothing) -> (s, len)
        (Nothing, _) -> (0, len)
```

**Hybrid Approach Rationale**:
- Linear scan is faster than binary search for small datasets (< 1000 patterns) due to low overhead
- Binary search provides safety for large caches, though growth beyond 10K patterns is unlikely in practice
- The "specificity range" heuristic bridges the two approaches

### 2. **Insertion and Maintenance**

```haskell
-- | Insert pattern maintaining sorted order
insertWithMaintenance :: OptimizedProgram -> VectorPatternCache -> VectorPatternCache
insertWithMaintenance optProg cache =
    let bitmask = wildcardPatternBitmask optProg
        newEntry = (bitmask, optProg)
        
        -- Add to vector
        newVector = Vector.snoc (sortedPatterns cache) newEntry
        
        -- Re-sort if we're getting large (optional - only every 100 insertions)
        needsResort = patternCount cache `mod` 100 == 0
        sortedVector = if needsResort
                       then Vector.modify (sortBySpecificity) newVector
                       else newVector
        
        -- Update statistics
        newStats = (cacheStats cache)
            { totalPatterns = patternCount cache + 1
            , memoryUsage = estimateMemoryUsage sortedVector
            }
    in cache
        { sortedPatterns = sortedVector
        , patternCount = patternCount cache + 1
        , cacheStats = newStats
        , lastModified = Just (getCurrentTime)  -- Would need IO
        }

-- | Estimate memory usage of cache
estimateMemoryUsage :: Vector.Vector (BitmapPattern, OptimizedProgram) -> Int
estimateMemoryUsage vec =
    let numPatterns = Vector.length vec
        bytesPerBitmask = 16 * 2  -- 16 Word16s
        bytesPerProgram = 200  -- Rough estimate
        bytesPerEntry = bytesPerBitmask + bytesPerProgram
    in numPatterns * bytesPerEntry
```

### 3. **Persistence Layer** (`PersistentCache` instance)

```haskell
instance PersistentCache VectorPatternCache where
    -- | Save entire cache to file as JSON
    saveCache filePath cache = do
        let patterns = Vector.toList (sortedPatterns cache)
            cacheable = map (\(_, optProg) -> optProg) patterns  -- OptimizedProgram is ToJSON
            jsonData = Aeson.toJSON cacheable
        try (ByteString.writeFile filePath (Aeson.encode jsonData)) >>= \case
            Left (err :: IOException) -> return $ Left $ SaveError (show err)
            Right () -> return $ Right ()
    
    -- | Load cache from file
    loadCache filePath = do
        content <- try (ByteString.readFile filePath)
        case content of
            Left (err :: IOException) -> 
                return $ Left $ LoadError (show err)
            Right bs -> case Aeson.decode bs of
                Nothing -> return $ Left $ LoadError "Failed to parse JSON"
                Just optProgs -> do
                    let bitmasks = map (\optProg -> 
                            (wildcardPatternBitmask optProg, optProg)) optProgs
                        sortedVec = Vector.fromList bitmasks
                        stats = CacheStats
                            { totalPatterns = length optProgs
                            , totalLookups = 0
                            , cacheHits = 0
                            , cacheMisses = 0
                            , avgLookupTime = 0.0
                            , memoryUsage = estimateMemoryUsage sortedVec
                            }
                    return $ Right VectorPatternCache
                        { sortedPatterns = sortedVec
                        , patternCount = length optProgs
                        , cacheStats = stats
                        , config = CacheConfig Nothing False (Just filePath)
                        , lastModified = Nothing
                        }
    
    -- | Append single pattern to file (incremental update)
    appendToCache filePath optProg cache = do
        let jsonLine = Aeson.encode optProg
        try (ByteString.appendFile filePath (jsonLine `ByteString.append` "\n")) >>= \case
            Left (err :: IOException) -> 
                return $ Left $ SaveError (show err)
            Right () -> return $ Right (insertPattern optProg cache)
```

**Persistence Strategy**:
- **Full save**: Complete JSON array of OptimizedPrograms
- **Incremental append**: JSONL format (one pattern per line) for streaming updates
- **Load-time reconstruction**: Rebuild vector with bitmap patterns from stored OptimizedPrograms

---

## Performance Analysis

### Lookup Complexity

| Scenario | Complexity | Practical Performance |
|----------|-----------|----------------------|
| **Small cache (< 1000)** | O(P × L) where P = patterns, L = 16 | **Very fast**: ~microseconds per lookup |
| **Large cache (> 1000)** | O(log P) binary range + O(C × L) scan | **Fast**: milliseconds even with 10K patterns |
| **Best case** | O(L) | Early termination when pattern matches |
| **Worst case** | O(P × L) | All patterns checked (only for no matches) |

**NO PROGRAM EXECUTION**: Pattern matching uses bitwise operations only, no interpreter simulation.

### Memory Usage

```
Per-pattern storage:
  - BitmapPattern: 16 Word16s = 32 bytes
  - OptimizedProgram overhead: ~200 bytes
  - Vector index: 8 bytes
  = ~240 bytes per pattern

Total for 1000 patterns: ~240 KB
Total for 10000 patterns: ~2.4 MB
```

### Comparison with Current Trie

| Metric | Trie | Vector + Binary Search |
|--------|------|----------------------|
| **Memory per pattern** | ~300 bytes (tree overhead) | ~240 bytes (vector) |
| **Lookup time (small)** | O(L) with pointers | O(P × L) cached |
| **Lookup time (large)** | O(L) with pointers | O(log P) range + scan |
| **Cache friendliness** | Poor (pointer chasing) | Excellent (contiguous memory) |
| **Persistence** | Complex (custom serialization) | Simple (JSON array) |
| **Implementation lines** | ~200 | ~150 |

---

## Implementation Roadmap

### Phase 1: Core Implementation (Week 1)
1. Create `WildcardCache/VectorCache.hs` with basic types
2. Implement `lookupPattern` with linear scan
3. Implement `insertPattern` with simple append
4. Add basic `getCacheStats` tracking

### Phase 2: Optimization (Week 2)
1. Implement sorting by specificity
2. Add binary search optimization
3. Profile and benchmark against Trie
4. Optimize bitmap matching (already mostly done)

### Phase 3: Persistence (Week 3)
1. Implement `PersistentCache` instance
2. Add JSONL incremental append
3. Add cache loading on startup
4. Test round-trip serialization

### Phase 4: Integration (Week 4)
1. Update `WildcardCache.hs` to support both Trie and Vector backends
2. Update command-line interface to allow backend selection
3. Add benchmarking comparisons
4. Document usage and configuration

---

## Integration with Existing Code

### Changes to `WildcardCache.hs`

```haskell
-- Existing code addition to CacheImplementation enum
data CacheImplementation 
    = VectorScanCache          -- NEW
    | BinarySearchVectorCache  -- NEW (with optimization)
    | TrieCache                -- Existing
    | PositionIndexCache       -- Future
    | BitMatrixCache           -- Future
    | DFACache                 -- Future
    | SignatureHashCache       -- Not recommended
    deriving (Show, Eq, Enum, Bounded)

-- Factory function for creating cache implementation
createCacheImplementation :: CacheImplementation -> CacheConfig -> IO SomeCacheImpl
createCacheImplementation VectorScanCache config = do
    cache <- createVectorCache config
    return $ SomeCache cache

createCacheImplementation BinarySearchVectorCache config = do
    cache <- createVectorCache config
    return $ SomeCache cache  -- Same type, different behavior on large caches

-- ... other implementations
```

### Compatibility Layer

```haskell
-- The VectorPatternCache is a drop-in replacement for TriePatternCache
-- All code using WildcardPatternCache interface works unchanged
lookupInCache program (SomeCache cache) statsTracker = do
    let result = lookupPattern program cache  -- Works with any implementation
    case result of
        Just _ -> CST.trackCacheHit statsTracker
        Nothing -> CST.trackCacheMiss statsTracker
    return result
```

---

## Testing Strategy

### Unit Tests

```haskell
-- Test pattern matching correctness
test_vectorCache_exactMatch :: Assertion
test_vectorCache_exactMatch = do
    let optProg = createSimpleOptimizedProgram [Required 8, Required 15]
    let cache = insertPattern optProg emptyVectorCache
    let result = lookupPattern [8, 15, 0, 0, ...] cache
    result `shouldBe` Just optProg

-- Test wildcard matching
test_vectorCache_wildcardMatch :: Assertion
test_vectorCache_wildcardMatch = do
    let optProg = createSimpleOptimizedProgram [Required 8, Wildcard]
    let cache = insertPattern optProg emptyVectorCache
    let result1 = lookupPattern [8, 0, 0, ...] cache
    let result2 = lookupPattern [8, 15, 0, ...] cache
    result1 `shouldBe` Just optProg
    result2 `shouldBe` Just optProg

-- Test AnyOf matching
test_vectorCache_anyOfMatch :: Assertion
test_vectorCache_anyOfMatch = do
    let optProg = createSimpleOptimizedProgram [Required 8, AnyOf [0..9]]
    let cache = insertPattern optProg emptyVectorCache
    let result1 = lookupPattern [8, 5, 0, ...] cache
    let result2 = lookupPattern [8, 10, 0, ...] cache  -- Should fail
    result1 `shouldBe` Just optProg
    result2 `shouldBe` Nothing

-- Test persistence round-trip
test_vectorCache_persistence :: Assertion
test_vectorCache_persistence = do
    cache1 <- createVectorCache defaultConfig
    let cache2 = insertPattern prog1 cache1
    let cache3 = insertPattern prog2 cache2
    
    saveCache "test.json" cache3 `shouldReturn` Right ()
    cache4 <- loadCache "test.json"
    
    cacheStats cache3 `shouldEqual` cacheStats cache4
```

### Integration Tests

```haskell
-- Test with actual search
test_vectorCache_searchIntegration :: Assertion
test_vectorCache_searchIntegration = do
    cache <- buildLargeCacheWithSearchResults 1000
    
    -- Verify cache hits on known patterns
    let knownProgram = [8, 15, 0, 0, ...]
    result <- lookupInCache knownProgram (SomeCache cache) statsTracker
    result `shouldNotBe` Nothing
    
    -- Verify statistics updated
    stats <- extractCacheStats (SomeCache cache)
    cacheHits stats > 0 `shouldBe` True
```

### Performance Benchmarks

```haskell
-- Benchmark: Linear scan vs binary search
benchmark_vectorCache_lookupPerformance :: IO ()
benchmark_vectorCache_lookupPerformance = do
    cache <- buildCacheWithNPatterns 10000
    
    putStrLn "Linear Scan Benchmark:"
    timeIt $ do
        for_ [1..1000] $ \_ -> do
            let program = generateRandomProgram
            lookupPattern program cache
    
    putStrLn "Binary Search Benchmark:"
    timeIt $ do
        for_ [1..1000] $ \_ -> do
            let program = generateRandomProgram
            binarySearchLookup program cache
```

---

## Risks and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|---------|-----------|
| **Pattern ordering affects performance** | Medium | Medium | Test with different sort strategies, profile with real data |
| **Binary search heuristic doesn't work well** | Low | Low | Fall back to linear scan, which is still fast enough |
| **Memory growth with many patterns** | Low | Low | Implement pattern deduplication, eviction policies |
| **JSON serialization is slow** | Low | Medium | Profile persistence, consider binary format if needed |
| **Bitmap matching has edge cases** | Very Low | High | Leverage proven implementation from WildcardPattern.hs |

---

## Success Metrics

### Performance Targets

1. **Lookup time**: < 100 microseconds average case for cache with 1000 patterns
2. **Insertion time**: < 1 millisecond even during re-sorting
3. **Memory efficiency**: < 250 bytes per pattern stored
4. **Persistence**: Save/load 1000 patterns in < 100ms

### Code Quality Targets

1. **Test coverage**: > 90% of cache code
2. **Documentation**: All public functions with type signatures and examples
3. **Benchmark suite**: Comparison with Trie implementation
4. **Zero panics**: Safe error handling in all code paths

### Search Integration

1. **Cache hit rate**: > 50% of lookups on typical searches
2. **Speedup factor**: 10x-50x improvement over non-cached execution per hit
3. **Overall search time**: Measurable improvement in time-to-solution for length 6-8 programs

---

## Future Enhancements

### Short Term (Post-Implementation)

1. **Deduplication**: Detect and merge equivalent patterns
2. **Eviction policies**: LRU eviction when cache exceeds memory limit
3. **Multi-level caching**: Separate caches for different program lengths
4. **Incremental loading**: Stream load large caches in chunks

### Long Term (Exploration)

1. **Compile to Position Index**: Convert mature cache to hierarchical position-based storage
2. **Hybrid search**: Use cache + specialized search for best performance
3. **Distributed caching**: Share cache across multiple search processes
4. **Machine learning**: Learn optimal sort order from usage patterns

---

## Conclusion

Direct Pattern Storage with Binary Search is an excellent next step for the caching infrastructure. It leverages the proven bitmap-based pattern matching already in place, provides simpler implementation than the Trie, offers better cache locality, and maintains the same correctness guarantees while potentially improving performance.

The phased implementation approach allows for gradual improvement, with each phase adding value independently. The simple persistence model (JSON) enables easy cache reuse across runs, which can compound performance benefits over time as the cache grows.
