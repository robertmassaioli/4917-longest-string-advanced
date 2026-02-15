# Generative Search Refactor Plan

## Current Problem

The current implementation generates ALL candidates as a lazy list and then filters/tests them. When we find a better program, we add its wildcard pattern to the trie and restart generation from scratch. This has several issues:

1. **Wildcard patterns are too broad**: When we add program `[0,0,0]`, the optimized pattern excludes ALL programs starting with 0 (256 programs instead of 1)
2. **Inefficient restarts**: We throw away the lazy list and regenerate from scratch
3. **Not truly incremental**: The trie updates don't incrementally prune the search space

## Proposed Solution

Instead of `generateCandidates :: Int -> GenerativeTrie -> [[Word8]]` (returns ALL candidates), implement:

```haskell
generateNextCandidate :: Int -> GenerativeTrie -> CandidateGenerator -> Maybe ([Word8], CandidateGenerator)
```

Where:
- **Input**: Program length, trie, current generator state
- **Output**: `Nothing` if exhausted, or `Just (program, nextState)` with the next valid candidate
- **Key property**: The returned program is GUARANTEED not to match any pattern in the trie

## Architecture

### 1. CandidateGenerator State

Track where we are in the search space:

```haskell
data CandidateGenerator = CandidateGenerator
    { genLength :: Int                    -- Target program length
    , genPosition :: Int                  -- Current position (0..length-1)
    , genPartial :: [Word8]               -- Partial program built so far (reversed)
    , genNextValues :: [[Word8]]          -- Stack of possible values at each position
    , genExhausted :: Bool                -- True when no more candidates
    }
```

### 2. Core Function: generateNextCandidate

**Algorithm**:
1. Start from current position with partial program
2. At each position, get allowed values from trie: `getAllowedValues partial trie`
3. Try next allowed value:
   - If found: advance to next position
   - If no more values at this position: backtrack to previous position
4. When we reach target length: emit complete program
5. Backtrack and continue until exhausted

**Key insight**: `getAllowedValues` already exists in GenerativeTrie and ensures we only try values that won't match forbidden patterns!

### 3. Search Loop

```haskell
searchForLongestOutput config initialTrie = do
    let gen0 = initGenerator (targetLength config) initialTrie
    loop gen0 initialTrie Nothing "" 0 0 0
  where
    loop gen trie bestProg bestOutput generated tested patternCount = do
        case generateNextCandidate (targetLength config) trie gen of
            Nothing -> 
                -- Exhausted all candidates
                return (bestProg, bestOutput, finalProgress, trie)
            
            Just (candidate, nextGen) -> do
                -- Test this candidate
                result <- runProgramWithDevice candidate
                case result of
                    Left _ -> 
                        -- Failed program, skip it
                        loop nextGen trie bestProg bestOutput (generated+1) tested patternCount
                    
                    Right (output, device) ->
                        if length output > length bestOutput
                        then do
                            -- Found better program!
                            -- Add its wildcard pattern to trie
                            let analysis = analyzeProgram candidate device
                                optimized = optimizeProgram analysis
                                updatedTrie = insertPattern optimized trie
                                -- IMPORTANT: Create NEW generator with updated trie
                                newGen = initGenerator (targetLength config) updatedTrie
                            
                            loop newGen updatedTrie (Just candidate) output (generated+1) (tested+1) (patternCount+1)
                        else
                            -- Not better, continue with same trie
                            loop nextGen trie bestProg bestOutput (generated+1) (tested+1) patternCount
```

### 4. Benefits

✅ **Truly incremental**: Each wildcard pattern immediately affects future candidates
✅ **No restarts needed**: Generator state can be updated without losing progress
✅ **Efficient**: Only generates candidates that don't match trie patterns
✅ **Clear semantics**: One candidate at a time, explicitly managed state
✅ **Correct**: Wildcard patterns work as designed (excluding equivalence classes)

## Implementation Steps

### Step 1: Define CandidateGenerator type
- State tracking for position in search space
- Stack-based backtracking state

### Step 2: Implement initGenerator
- Initialize generator for given length and trie
- Set up initial state at position 0

### Step 3: Implement generateNextCandidate
- Core generation logic with backtracking
- Uses `getAllowedValues` from trie
- Returns `Maybe (program, newState)`

### Step 4: Refactor searchForLongestOutput
- Replace lazy list generation with explicit loop
- Update generator when trie changes
- Track progress correctly

### Step 5: Update tests
- Fix expectations to account for wildcard patterns
- Test that generator respects trie constraints
- Test backtracking and exhaustion

### Step 6: Remove old generateCandidates functions
- Keep for backward compatibility if needed
- Or deprecate and update all callsites

## Key Decision Points

### Question 1: When to reset generator?
**Option A**: Always create new generator when trie updates (simpler, potentially wasteful)
**Option B**: Try to update generator state incrementally (complex, more efficient)
**Recommendation**: Start with Option A for correctness, optimize to B later if needed

### Question 2: Should we still use wildcard patterns?
**Yes!** The whole point is to leverage wildcard patterns to exclude large equivalence classes. The current approach of excluding single programs defeats the purpose.

### Question 3: What about heuristic ordering?
We can still support it by having `getAllowedValues` return values in heuristic order instead of sequential order.

## Expected Results

With this approach, when we find program `[0,0,0]`:
- Its wildcard pattern `0***************` correctly excludes ~256 programs
- The generator never generates any programs matching that pattern
- We continue from the next valid candidate (e.g., `[1,0,0]`)
- The test showing 4096 → 3840 candidates is CORRECT behavior

The tests need to be updated to expect this behavior, not to expect single-program exclusion.

## Migration Strategy

1. Implement new functions alongside existing ones
2. Update `searchForLongestOutput` to use new approach
3. Run tests and fix expectations
4. Verify search still finds correct optimal programs
5. Measure performance improvement
6. Document the wildcard pattern behavior clearly
