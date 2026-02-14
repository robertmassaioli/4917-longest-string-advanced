# Inverted Trie Generative Search - Implementation Plan

## Executive Summary

This document provides a comprehensive implementation plan for the **Inverted Trie Generative Search** system. This new approach generates only valid candidate programs by integrating wildcard pattern constraints directly into the generation process, avoiding the wasteful "generate-then-filter" pattern of the current implementation.

**Key Innovation**: Instead of generating all 16^N programs and then filtering them against wildcard patterns, we build an inverted trie from the patterns and use it to generate only programs that don't match any known patterns.

---

## 1. Architecture Overview

### 1.1 New Modules (4 Total)

```
haskell-impl/src/
├── GenerativeTrie.hs          # Core inverted trie data structure
├── GenerativeSearch.hs        # Lazy candidate generation engine
├── GenerativeStats.hs         # Statistics and performance tracking
└── Commands/
    └── GenSearch.hs           # CLI command implementation
```

### 1.2 Integration with Existing Modules

**Reused (No Changes):**
- `WildcardPattern.hs` - Pattern representation
- `TrackedProcessor.hs` - Program execution
- `ExecutionTracing.hs` - Execution analysis
- `WildcardCache.hs` / `WildcardCache.Trie.hs` - Pattern storage
- `CLI.hs` - CLI framework (just add new command)

**New Dependencies:**
- `containers` (already in use) - For `IntSet` and `IntMap`
- `vector` (already in use) - For efficient array operations

---

## 2. Module 1: GenerativeTrie.hs

### 2.1 Purpose

Implements the inverted trie data structure that stores forbidden program patterns and provides efficient candidate validation during generation.

### 2.2 Core Data Structure

```haskell
module GenerativeTrie
    ( GenerativeTrie
    , empty
    , insertPattern
    , isAllowedAtPosition
    , getAllowedValues
    , getTrieStats
    ) where

import qualified Data.IntSet as IS
import qualified Data.IntMap.Strict as IM
import WildcardPattern (WildcardPattern, PatternConstraint(..))

-- | Inverted trie node representing forbidden values at a position
data TrieNode = TrieNode
    { forbiddenValues :: !IS.IntSet      -- Values forbidden at this position
    , childNodes      :: !(IM.IntMap TrieNode)  -- Map from value -> next node
    } deriving (Show, Eq)

-- | The generative trie stores all forbidden patterns
newtype GenerativeTrie = GenerativeTrie
    { rootNode :: TrieNode
    } deriving (Show, Eq)

-- | Statistics about the trie
data TrieStats = TrieStats
    { totalNodes       :: !Int
    , totalPatterns    :: !Int
    , maxDepth         :: !Int
    , avgBranchFactor  :: !Double
    , memoryEstimateKB :: !Int
    } deriving (Show, Eq)
```

### 2.3 Key Operations

#### 2.3.1 Empty Trie

```haskell
empty :: GenerativeTrie
empty = GenerativeTrie (TrieNode IS.empty IM.empty)
```

#### 2.3.2 Insert Pattern

```haskell
-- | Insert a wildcard pattern into the trie
-- Converts pattern to exclusion constraints at each position
insertPattern :: WildcardPattern -> GenerativeTrie -> GenerativeTrie
insertPattern pattern trie = 
    let constraints = extractConstraints pattern
    in foldl' insertConstraintPath trie (expandConstraints constraints)

-- Helper: Extract constraints from pattern (position -> allowed values)
extractConstraints :: WildcardPattern -> [(Int, [Int])]

-- Helper: Expand constraint paths for all combinations
expandConstraints :: [(Int, [Int])] -> [[Int]]

-- Helper: Insert a single concrete path into trie
insertConstraintPath :: GenerativeTrie -> [Int] -> GenerativeTrie
```

**Algorithm for `insertConstraintPath`:**
1. Start at root node
2. For each position `i` with value `v`:
   - Add `v` to current node's `forbiddenValues`
   - If children exist for other values, recurse into them
   - Create child node if needed for next position
3. Mark path as complete when pattern ends

#### 2.3.3 Query Operations

```haskell
-- | Check if a value is allowed at a given position in a partial program
isAllowedAtPosition :: GenerativeTrie 
                    -> [Int]  -- Partial program built so far
                    -> Int    -- Position to check
                    -> Int    -- Value to test
                    -> Bool

-- | Get all allowed values at a position for a partial program
getAllowedValues :: GenerativeTrie 
                 -> [Int]  -- Partial program built so far
                 -> Int    -- Position to check
                 -> [Int]  -- Allowed values [0..15]
```

**Algorithm for `getAllowedValues`:**
1. Traverse trie following the partial program path
2. At target position, return [0..15] minus `forbiddenValues` of all reachable nodes
3. If no constraints exist at this depth, return [0..15]

#### 2.3.4 Statistics

```haskell
getTrieStats :: GenerativeTrie -> TrieStats
-- Count nodes, calculate depth, estimate memory
```

### 2.4 Edge Cases

1. **Empty Patterns**: Pattern with all wildcards → no nodes added
2. **Overlapping Patterns**: Multiple patterns constraining same position → union of forbidden values
3. **Partial Matches**: Programs shorter than pattern → only constrain relevant positions
4. **AnyOf Constraints**: `[0-9]` expands to 10 separate branches in the trie

### 2.5 Testing

```haskell
-- Unit tests in test/GenerativeTrieSpec.hs
spec :: Spec
spec = do
    describe "empty" $ 
        it "allows all values at all positions"
    
    describe "insertPattern" $ do
        it "forbids exact matches"
        it "handles AnyOf constraints"
        it "merges overlapping patterns"
    
    describe "getAllowedValues" $ do
        it "returns [0..15] for unconstrained positions"
        it "excludes forbidden values"
        it "handles partial program paths"
```

---

## 3. Module 2: GenerativeSearch.hs

### 3.1 Purpose

Implements the lazy candidate generation algorithm that produces only valid programs using the inverted trie for constraint checking.

### 3.2 Core Functions

```haskell
module GenerativeSearch
    ( generateCandidates
    , GenerationConfig(..)
    , GenerationStats(..)
    , updateTrieWithPattern
    ) where

import GenerativeTrie
import WildcardPattern
import TrackedProcessor (TrackedProgram, executeProgram)

-- | Configuration for generation
data GenerationConfig = GenerationConfig
    { targetLength    :: !Int
    , maxCandidates   :: !(Maybe Int)  -- Limit total generated
    , sortByHeuristic :: !Bool         -- Apply heuristic ordering
    , verboseLogging  :: !Bool
    } deriving (Show, Eq)

-- | Statistics during generation
data GenerationStats = GenerationStats
    { candidatesGenerated :: !Int
    , candidatesSkipped   :: !Int
    , patternsInTrie      :: !Int
    , executionCount      :: !Int
    , bestOutputLength    :: !Int
    , bestProgram         :: !(Maybe [Int])
    } deriving (Show, Eq)
```

### 3.3 Main Generation Algorithm

```haskell
-- | Generate candidates lazily using trie constraints
generateCandidates :: GenerativeTrie 
                   -> GenerationConfig 
                   -> [TrackedProgram]  -- Lazy list of valid candidates
generateCandidates trie config = 
    generateAtPosition trie config [] 0

-- | Recursive generation at a specific position
generateAtPosition :: GenerativeTrie 
                   -> GenerationConfig
                   -> [Int]  -- Partial program
                   -> Int    -- Current position
                   -> [TrackedProgram]
generateAtPosition trie config partial pos
    | pos >= targetLength config = [programFromList partial]
    | otherwise = do
        let allowedValues = getAllowedValues trie partial pos
        value <- allowedValues
        generateAtPosition trie config (partial ++ [value]) (pos + 1)
```

**Key Properties:**
- **Lazy**: Uses list monad for lazy generation
- **Pruning**: Only generates values allowed by trie
- **Complete**: Generates all non-excluded programs exactly once
- **Efficient**: No redundant generation or filtering

### 3.4 Live Trie Updates

```haskell
-- | Update trie during search when new pattern found
updateTrieWithPattern :: GenerativeTrie 
                      -> WildcardPattern 
                      -> (GenerativeTrie, UpdateStats)
updateTrieWithPattern trie pattern =
    let newTrie = insertPattern pattern trie
        stats = calculateUpdateImpact trie newTrie pattern
    in (newTrie, stats)

data UpdateStats = UpdateStats
    { patternsAdded       :: !Int
    , nodesAdded          :: !Int
    , candidatesEliminated :: !Integer  -- Estimated
    } deriving (Show, Eq)
```

### 3.5 Heuristic Ordering (Optional Enhancement)

```haskell
-- | Order values by heuristic score (jump ops first, etc.)
orderByHeuristic :: Int -> [Int] -> [Int]
orderByHeuristic position values =
    sortOn (negate . scoreValue position) values

-- Heuristic: Favor jumps, loops, and memory operations
scoreValue :: Int -> Int -> Int
scoreValue pos val
    | val >= 13 && val <= 15 = 10  -- JMP, JZ, JNZ
    | val >= 9 && val <= 12  = 8   -- LOAD/STORE
    | val == 8               = 6   -- PRINT
    | val >= 1 && val <= 6   = 4   -- Arithmetic
    | otherwise              = 1   -- HALT, NOP
```

### 3.6 Testing

```haskell
-- Integration tests in test/GenerativeSearchSpec.hs
spec :: Spec
spec = do
    describe "generateCandidates" $ do
        it "generates all candidates when trie is empty"
        it "skips forbidden candidates"
        it "produces correct count for length 3"
        it "respects maxCandidates limit"
    
    describe "updateTrieWithPattern" $ do
        it "integrates new patterns during search"
        it "updates statistics correctly"
```

---

## 4. Module 3: GenerativeStats.hs

### 4.1 Purpose

Track and report detailed statistics about the generative search process.

### 4.2 Data Structure

```haskell
module GenerativeStats
    ( StatsTracker
    , emptyStats
    , recordCandidate
    , recordSkip
    , recordExecution
    , recordPattern
    , getStatsReport
    , printProgressReport
    ) where

import Data.Time (UTCTime, NominalDiffTime)
import qualified Data.Map.Strict as M

data StatsTracker = StatsTracker
    { startTime           :: !UTCTime
    , candidatesGenerated :: !Int
    , candidatesSkipped   :: !Int
    , candidatesExecuted  :: !Int
    , patternsFound       :: !Int
    , bestResult          :: !(Maybe (Int, [Int], String))  -- (length, program, output)
    , outputLengthHist    :: !(M.Map Int Int)  -- output length -> count
    , positionSkipCounts  :: !(M.Map Int Int)  -- position -> skip count
    } deriving (Show)

data StatsReport = StatsReport
    { totalRuntime        :: !NominalDiffTime
    , candidatesPerSecond :: !Double
    , skipRate            :: !Double
    , bestOutputLength    :: !Int
    , patternsDiscovered  :: !Int
    , searchEfficiency    :: !Double  -- (generated / theoretical_max)
    } deriving (Show)
```

### 4.3 Key Functions

```haskell
emptyStats :: IO StatsTracker
recordCandidate :: StatsTracker -> StatsTracker
recordSkip :: Int -> StatsTracker -> StatsTracker  -- position where skipped
recordExecution :: Int -> [Int] -> String -> StatsTracker -> StatsTracker
recordPattern :: WildcardPattern -> StatsTracker -> StatsTracker
getStatsReport :: StatsTracker -> IO StatsReport
printProgressReport :: StatsTracker -> Int -> IO ()  -- Print every N candidates
```

---

## 5. Module 4: Commands/GenSearch.hs

### 5.1 Purpose

CLI command implementation that ties everything together.

### 5.2 Command Structure

```haskell
module Commands.GenSearch (genSearchCommand) where

import GenerativeTrie
import GenerativeSearch
import GenerativeStats
import WildcardPattern
import WildcardCache
import TrackedProcessor
import CLI (Command(..))

genSearchCommand :: Command
genSearchCommand = Command
    { commandName = "gen-search"
    , commandDesc = "Generative search using inverted trie"
    , commandParser = genSearchOptions
    , commandAction = runGenSearch
    }

data GenSearchOptions = GenSearchOptions
    { optLength       :: !Int
    , optResume       :: !Bool          -- Load existing patterns
    , optStatsEnabled :: !Bool
    , optLimit        :: !(Maybe Int)   -- Limit candidates
    , optHeuristic    :: !Bool          -- Use heuristic ordering
    , optVerbose      :: !Bool
    } deriving (Show)
```

### 5.3 Main Execution Flow

```haskell
runGenSearch :: GenSearchOptions -> IO ()
runGenSearch opts = do
    -- Phase 1: Load existing wildcard patterns
    cachedPatterns <- if optResume opts
        then loadExistingPatterns (optLength opts)
        else return []
    
    -- Phase 2: Build initial trie
    let initialTrie = foldl' (flip insertPattern) empty cachedPatterns
    putStrLn $ "Loaded " ++ show (length cachedPatterns) ++ " patterns into trie"
    
    -- Phase 3: Initialize statistics
    stats <- emptyStats
    
    -- Phase 4: Generate and test candidates
    let config = GenerationConfig
            { targetLength = optLength opts
            , maxCandidates = optLimit opts
            , sortByHeuristic = optHeuristic opts
            , verboseLogging = optVerbose opts
            }
    
    -- Phase 5: Main search loop with live updates
    finalStats <- searchWithLiveUpdates initialTrie config stats
    
    -- Phase 6: Report results
    printFinalReport finalStats

-- | Main search loop: generate, execute, update trie
searchWithLiveUpdates :: GenerativeTrie 
                      -> GenerationConfig 
                      -> StatsTracker 
                      -> IO StatsTracker
searchWithLiveUpdates initialTrie config initialStats = 
    go initialTrie initialStats (generateCandidates initialTrie config)
  where
    go trie stats [] = return stats
    go trie stats (candidate:rest) = do
        -- Execute program
        let (output, trace) = executeProgram candidate
        let outputLen = length output
        
        -- Update stats
        let stats' = recordExecution outputLen candidate output stats
        
        -- Check if new best
        when (outputLen > bestOutputLength stats') $ do
            putStrLn $ "NEW BEST: " ++ show candidate ++ " -> " ++ show outputLen ++ " chars"
        
        -- Generate pattern if beneficial
        maybePattern <- generatePatternIfUseful candidate trace outputLen
        
        case maybePattern of
            Nothing -> go trie stats' rest
            Just pattern -> do
                -- Update trie with new pattern
                let (newTrie, updateStats) = updateTrieWithPattern trie pattern
                let stats'' = recordPattern pattern stats'
                
                putStrLn $ "Pattern added: eliminates ~" ++ 
                           show (candidatesEliminated updateStats) ++ " candidates"
                
                -- Continue with updated trie (rest is lazy, so already filtered!)
                go newTrie stats'' rest
```

### 5.4 Pattern Generation Strategy

```haskell
-- | Decide if we should generate a pattern for this result
generatePatternIfUseful :: [Int] -> ExecutionTrace -> Int -> IO (Maybe WildcardPattern)
generatePatternIfUseful program trace outputLen = do
    -- Same logic as OptimizedSearch.hs
    -- Generate pattern if:
    -- 1. Program loops or has interesting behavior
    -- 2. Output length is notable
    -- 3. Pattern would eliminate significant search space
    return $ analyzeAndGeneratePattern program trace
```

### 5.5 CLI Integration

```haskell
-- In CLI.hs, add to command list:
allCommands :: [Command]
allCommands = 
    [ searchCommand
    , optimizedSearchCommand
    , genSearchCommand        -- NEW
    , cacheDemoCommand
    , benchmarkCommand
    , testCommand
    ]
```

### 5.6 Usage Examples

```bash
# Basic search for length 7
stack exec cli4917 -- gen-search --length 7

# Resume with existing patterns
stack exec cli4917 -- gen-search --length 8 --resume

# With heuristic ordering and limit
stack exec cli4917 -- gen-search --length 7 --heuristic --limit 1000000

# Verbose mode with statistics
stack exec cli4917 -- gen-search --length 6 --stats --verbose
```

---

## 6. Algorithm Deep Dive

### 6.1 Core Generation Algorithm

**Input**: 
- Inverted trie with forbidden patterns
- Target program length N

**Output**:
- Lazy stream of candidate programs (length N)

**Algorithm**:
```
function GENERATE(trie, partialProgram, position, targetLength):
    if position == targetLength:
        yield partialProgram
        return
    
    allowedValues = GET_ALLOWED_VALUES(trie, partialProgram, position)
    
    for value in allowedValues:
        newPartial = partialProgram + [value]
        yield from GENERATE(trie, newPartial, position + 1, targetLength)

function GET_ALLOWED_VALUES(trie, partialProgram, position):
    node = TRAVERSE_TRIE(trie, partialProgram)
    if node is null:
        return [0..15]  // No constraints
    else:
        return [0..15] - node.forbiddenValues
```

**Complexity**:
- **Time per candidate**: O(N) where N = program length
- **Space**: O(N) for recursion stack + O(M) for trie (M = total pattern nodes)
- **Total candidates**: Up to 16^N (but typically much less due to pruning)

### 6.2 Trie Traversal

```
function TRAVERSE_TRIE(trie, partialProgram):
    node = trie.root
    for value in partialProgram:
        if value in node.forbiddenValues:
            return null  // This path is forbidden
        if value in node.childNodes:
            node = node.childNodes[value]
        else:
            return null  // No more constraints along this path
    return node
```

### 6.3 Pattern Insertion

```
function INSERT_PATTERN(trie, pattern):
    paths = EXPAND_PATTERN_TO_PATHS(pattern)
    for path in paths:
        INSERT_PATH(trie, path)

function INSERT_PATH(trie, path):
    node = trie.root
    for (position, value) in enumerate(path):
        node.forbiddenValues.add(value)
        if value not in node.childNodes:
            node.childNodes[value] = NEW_NODE()
        node = node.childNodes[value]
```

**Example**: Pattern `8[0-9]1340***********`
- Expands to 10 paths: `[8,0,13,4,0]`, `[8,1,13,4,0]`, ..., `[8,9,13,4,0]`
- Each path creates/updates nodes at depth 0-4

---

## 7. Performance Analysis

### 7.1 Expected Speedup

**Current `optimized-search` approach:**
```
Generate all: 16^N candidates
Filter out: ~(reduction_factor × num_patterns) candidates
Execute: remaining candidates
```

**New `gen-search` approach:**
```
Generate only: 16^N - (eliminated by trie) candidates
Execute: all generated candidates
```

**Speedup Factor Calculation**:
- If patterns eliminate 90% of search space: **10x speedup**
- If patterns eliminate 95% of search space: **20x speedup**
- If patterns eliminate 99% of search space: **100x speedup**

### 7.2 Memory Usage

**Trie Memory**:
- Each node: ~48 bytes (IntSet + IntMap overhead)
- For 100 patterns averaging 5 constraints each: ~24 KB
- For 1000 patterns: ~240 KB
- Still far less than generating millions of candidates

### 7.3 Benchmark Targets

| Length | Total Space | Expected Elimination | Expected Time |
|--------|-------------|---------------------|---------------|
| 3      | 4,096       | 50%                 | < 1 sec       |
| 4      | 65,536      | 70%                 | < 5 sec       |
| 5      | 1,048,576   | 85%                 | < 1 min       |
| 6      | 16,777,216  | 90%                 | < 10 min      |
| 7      | 268,435,456 | 95%                 | < 2 hours     |
| 8      | 4,294,967,296 | 98%               | < 24 hours    |

---

## 8. Integration & Compatibility

### 8.1 Backward Compatibility

**No Changes Required To:**
- Existing commands: `search`, `optimized-search`, `benchmark`, etc.
- Existing modules: All processor, caching, and pattern modules remain unchanged
- Existing cache files: Can be loaded and used by new command

**New Command Only:**
- `gen-search` is a completely separate command
- Users can compare results between `optimized-search` and `gen-search`
- Both approaches can coexist indefinitely

### 8.2 Pattern Reuse

```haskell
-- Load patterns from existing cache
loadExistingPatterns :: Int -> IO [WildcardPattern]
loadExistingPatterns len = do
    cache <- loadWildcardCache len
    return $ getAllPatterns cache
```

The new system can leverage all the patterns discovered by previous `optimized-search` runs!

### 8.3 Validation

```haskell
-- Verify gen-search produces same results as optimized-search
validateGenSearch :: Int -> IO Bool
validateGenSearch len = do
    optimizedResults <- runOptimizedSearch len
    genResults <- runGenSearch len
    return $ optimizedResults == genResults
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

**GenerativeTrie Tests**:
- Empty trie behavior
- Single pattern insertion
- Multiple pattern insertion
- Overlapping patterns
- Query operations
- Statistics calculation

**GenerativeSearch Tests**:
- Empty trie → generates all candidates
- Single pattern → excludes matching candidates
- Multiple patterns → correct exclusions
- Lazy evaluation verification
- Pattern update during search

### 9.2 Integration Tests

**End-to-End Tests**:
```haskell
describe "gen-search command" $ do
    it "finds same best programs as optimized-search for length 3" $ do
        genResult <- runGenSearchPure 3
        optResult <- runOptimizedSearchPure 3
        bestProgram genResult `shouldBe` bestProgram optResult
    
    it "generates fewer candidates than 16^N" $ do
        stats <- runGenSearchWithStats 4
        candidatesGenerated stats `shouldSatisfy` (< 65536)
```

### 9.3 Performance Tests

**Benchmark Suite**:
```haskell
benchmarks :: Benchmark
benchmarks = bgroup "gen-search"
    [ bench "length 3" $ nfIO (runGenSearch 3)
    , bench "length 4" $ nfIO (runGenSearch 4)
    , bench "length 5" $ nfIO (runGenSearch 5)
    ]
```

**Comparison Tests**:
- Compare runtime: gen-search vs optimized-search
- Compare memory: trie overhead vs candidate lists
- Compare correctness: verify same results

---

## 10. Implementation Timeline

### Week 1: Foundation (Module 1 & 2 Core)

**Days 1-2: GenerativeTrie.hs**
- [ ] Implement data structures
- [ ] Implement `empty`, `insertPattern`
- [ ] Implement query operations
- [ ] Write unit tests
- [ ] Test with sample patterns

**Days 3-4: GenerativeSearch.hs (Basic)**
- [ ] Implement `generateCandidates` (basic version)
- [ ] Implement `generateAtPosition` recursion
- [ ] Test lazy generation
- [ ] Write integration tests

**Day 5: Integration Test**
- [ ] Test GenerativeTrie + GenerativeSearch together
- [ ] Verify candidate generation matches expectations
- [ ] Fix any bugs discovered

### Week 2: CLI & Live Updates (Modules 3 & 4)

**Days 6-7: GenerativeStats.hs**
- [ ] Implement statistics tracking
- [ ] Implement progress reporting
- [ ] Write formatting functions
- [ ] Test statistics calculations

**Days 8-9: Commands/GenSearch.hs**
- [ ] Implement CLI command structure
- [ ] Implement main search loop
- [ ] Implement pattern loading
- [ ] Test CLI integration

**Day 10: Live Pattern Updates**
- [ ] Implement `updateTrieWithPattern`
- [ ] Implement pattern generation hooks
- [ ] Test live update during search
- [ ] Verify correctness

### Week 3: Polish & Performance

**Days 11-12: Performance Tuning**
- [ ] Profile trie operations
- [ ] Optimize hot paths
- [ ] Add heuristic ordering
- [ ] Benchmark against optimized-search

**Days 13-14: Testing & Documentation**
- [ ] Run full test suite
- [ ] Add property-based tests
- [ ] Write usage documentation
- [ ] Create example runs

**Day 15: Final Review**
- [ ] Code review
- [ ] Performance validation
- [ ] Documentation review
- [ ] Prepare for merge

---

## 11. Success Criteria

### 11.1 Correctness

✅ **Must Pass:**
- Generates all non-excluded candidates for empty trie
- Correctly excludes all candidates matching patterns
- Produces same best results as `optimized-search`
- No false negatives (missed valid candidates)
- No false positives (generated forbidden candidates)

### 11.2 Performance

✅ **Target Metrics:**
- **Length 6**: < 10 minutes (vs hours with current approach)
- **Length 7**: < 2 hours (vs days/weeks with current approach)
- **Speedup**: 10-30x faster than `optimized-search`
- **Memory**: Trie overhead < 1 MB for typical workloads

### 11.3 Integration

✅ **Requirements:**
- No changes to existing commands
- Seamless pattern reuse from cache
- Compatible with all existing modules
- Clear separation of concerns

### 11.4 Usability

✅ **User Experience:**
- Clear progress reporting
- Meaningful statistics
- Graceful handling of Ctrl-C
- Resume capability
- Helpful error messages

---

## 12. Risks & Mitigation

### 12.1 Risk: Trie Memory Explosion

**Scenario**: Patterns with many `AnyOf` constraints create exponential trie nodes

**Mitigation**:
- Limit pattern expansion during insertion
- Use memory-efficient IntSet representation
- Monitor trie size and warn if excessive
- Implement trie pruning if needed

### 12.2 Risk: Generation Still Too Slow

**Scenario**: Even with pruning, length 8+ is impractical

**Mitigation**:
- Add heuristic ordering to find good solutions faster
- Implement early termination when "good enough" solution found
- Add multi-threading for candidate generation
- Consider hybrid approach: use trie for first N positions, then filter

### 12.3 Risk: Pattern Updates Invalidate Lazy Stream

**Scenario**: Updating trie mid-search doesn't affect already-generated tail

**Mitigation**:
- This is actually handled correctly by lazy evaluation
- New patterns only affect future generations
- Document this behavior clearly
- Consider batch updates at checkpoints

### 12.4 Risk: Compatibility Issues

**Scenario**: New modules break existing functionality

**Mitigation**:
- Keep new modules completely separate
- No modifications to existing modules
- Comprehensive integration tests
- Side-by-side validation with `optimized-search`

---

## 13. Future Enhancements

### 13.1 Phase 2 Ideas (Post-Initial Implementation)

1. **Parallel Generation**
   - Partition search space by first N positions
   - Generate candidates in parallel threads
   - Merge results efficiently

2. **Smart Heuristics**
   - Machine learning to predict high-value candidates
   - Adaptive heuristic weights based on discovered patterns
   - Prioritize unexplored regions of search space

3. **Incremental Trie Building**
   - Start with empty trie
   - Build trie incrementally as patterns discovered
   - Dynamically adjust generation strategy

4. **Trie Compression**
   - Merge equivalent subtrees
   - Share common prefixes
   - Reduce memory footprint

5. **Web Interface**
   - Real-time visualization of search progress
   - Interactive trie exploration
   - Pattern management UI

---

## 14. Open Questions

Before implementation, we should decide:

1. **Pattern Expansion Limit**: Should we limit `AnyOf` expansion to prevent trie explosion?
   - **DECISION**: Don't limit anything if it prevents us from finding valid programs. Full expansion allowed.

2. **Resume Strategy**: How to handle resume with partially-built trie?
   - **DECISION**: Save trie to disk alongside patterns for seamless resume capability.

3. **Progress Reporting Frequency**: How often to print statistics?
   - **DECISION**: Print statistics when whichever is longer: 10,000 iterations have passed OR 10 seconds since last message.

4. **Heuristic Weights**: What initial weights for heuristic scoring?
   - **DECISION**: Use the example heuristic system already generated. Start with those weights.

5. **Memory Limits**: Should we enforce max trie size?
   - **DECISION**: No hard limits. Monitor memory usage through other means.

---

## 15. Conclusion

This implementation plan provides a comprehensive roadmap for building the **Inverted Trie Generative Search** system. The approach is:

- **Architecturally Sound**: Clean separation of concerns with 4 focused modules
- **Backward Compatible**: No changes to existing code
- **Testable**: Clear unit and integration test strategy
- **Performant**: Expected 10-30x speedup with low memory overhead
- **Extensible**: Clear path for future enhancements

The 3-week timeline is realistic and includes buffer for testing and refinement. Upon completion, we'll have a powerful new search strategy that makes length 7-8 searches practical and opens the door to exploring even longer programs.

**Next Steps**: Await approval, then begin Week 1 implementation! 🚀
