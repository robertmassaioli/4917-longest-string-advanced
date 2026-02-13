# TrackedProcessor Performance Optimization Analysis

## Current Performance Profile
- **Baseline**: Regular Processor runs at ~163ns per step
- **TrackedProcessor**: Runs at ~419ns per step (2.57x slower)
- **Performance Gap**: The TrackedProcessor has significant overhead from tracking multiple data structures

## Root Cause Analysis

The TrackedProcessor maintains extensive tracking state that causes performance bottlenecks:
1. **Multiple Set operations** for `instructionLocations` and `operandLocations`
2. **Complex Map operations** for `detailedUsage` tracking
3. **String allocations** for instruction names in detailed tracking
4. **Redundant memory accesses** for detailed usage recording
5. **Set union/insert operations** on every instruction step

## Performance Optimization Recommendations

### 1. **Optimize Detailed Usage Map Structure** 
**Likelihood of Success: HIGH (85%)**

**Problem**: The `detailedUsage` Map uses `Int` keys and complex `MemoryUsage` values, causing frequent Map lookups and expensive insertions on every memory access.

**Solution**: 
- Replace `Map Int MemoryUsage` with a fixed-size array `Array 16 MemoryUsage`
- Use `STArray` for in-place updates during execution, then freeze to immutable array
- Pre-allocate `MemoryUsage` structures and update in-place rather than rebuilding
- Use `IntMap` instead of `Map Int` for better performance with small integer keys

**Expected Improvement**: 25-35% performance gain
```haskell
-- Instead of Map Int MemoryUsage
detailedUsage :: Array 16 (IORef MemoryUsage)

-- Or using IntMap for better integer key performance  
detailedUsage :: IntMap MemoryUsage

-- Update becomes O(1) array access instead of O(log n) Map operation
updateUsage :: Int -> MemoryUsage -> TrackedDevice -> TrackedDevice
updateUsage pos usage device = 
  device { detailedUsage = detailedUsage device // [(pos, usage)] }
```

### 2. **Replace Sets with Bit Vectors**
**Likelihood of Success: HIGH (85%)**

**Problem**: `Set Int` operations for 16-element memory space are overkill and slow.

**Solution**:
- Use `Word16` bit vectors instead of `Set Int` for `instructionLocations` and `operandLocations`
- Memory positions 0-15 can be represented as bits in a single word
- Set operations become bitwise OR, AND, XOR - orders of magnitude faster

**Expected Improvement**: 20-30% performance gain
```haskell
type MemoryAccessMask = Word16

setMemoryAccess :: Int -> MemoryAccessMask -> MemoryAccessMask
setMemoryAccess pos mask = mask .|. (1 `shiftL` pos)

checkMemoryAccess :: Int -> MemoryAccessMask -> Bool  
checkMemoryAccess pos mask = mask .&. (1 `shiftL` pos) /= 0
```

### 3. **Lazy Detailed Usage Recording**
**Likelihood of Success: MEDIUM-HIGH (75%)**

**Problem**: `Map.insert` and `Map.lookup` operations happen on every memory access, even when the detailed usage data isn't immediately needed.

**Solution**:
- Store access events in a more efficient structure (like a small array or strict list)
- Only build the full `MemoryUsage` structure when `getDetailedUsage` is called
- Use difference lists for efficient appending of usage events

**Expected Improvement**: 15-25% performance gain
```haskell
data AccessEvent = AccessEvent
  { eventPos :: {-# UNPACK #-} !Int
  , eventType :: !AccessType  -- enum instead of string
  , eventStep :: {-# UNPACK #-} !Int
  }

-- Build detailed usage on demand
buildDetailedUsage :: [AccessEvent] -> Map Int MemoryUsage
```

### 4. **Eliminate String Allocations**
**Likelihood of Success: HIGH (90%)**

**Problem**: `getInstructionName` allocates strings on every instruction execution.

**Solution**:
- Replace instruction name strings with an `InstructionType` enum
- Use `{-# UNPACK #-}` pragmas for small data types
- Pre-allocate instruction name strings as constants if strings are truly needed

**Expected Improvement**: 10-15% performance gain
```haskell
data InstructionType = HALT | ADD | SUB | INCR0 | INCR1 | DECR0 | DECR1 | NOP | PRINT | LOADR0 | LOADR1 | STORER0 | STORER1 | JMP | JZ | JNZ | UNKNOWN
  deriving (Show, Eq, Enum, Bounded)

getInstructionType :: Byte -> InstructionType
getInstructionType = toEnum . fromIntegral . min 16
```

### 5. **Optimize Record Updates with Strict Fields**
**Likelihood of Success: MEDIUM (70%)**

**Problem**: Record updates create intermediate values and may cause unnecessary allocations.

**Solution**:
- Add `{-# UNPACK #-}` pragmas to small numeric fields
- Use strict fields to prevent accumulation of thunks
- Consider using `StateT` monad for stateful updates instead of explicit record updates

**Expected Improvement**: 5-10% performance gain
```haskell
data TrackedDevice = TrackedDevice
  { pc :: {-# UNPACK #-} !Byte
  , r0 :: {-# UNPACK #-} !Byte  
  , r1 :: {-# UNPACK #-} !Byte
  , outputLength :: {-# UNPACK #-} !Int
  , steps :: {-# UNPACK #-} !Int
  , r0WasConsumed :: !Bool
  -- etc.
  }
```

## Implementation Strategy

### Phase 1: Quick Wins (Easiest to implement)
1. Add UNPACK pragmas and strict fields
2. Replace instruction name strings with enums
3. Implement bit vector memory tracking

### Phase 2: Structural Changes (Medium effort)
1. Optimize detailed usage Map structure (Array or IntMap)
2. Implement lazy detailed usage recording

### Phase 3: Advanced Optimizations (Higher effort)
1. Profile-guided optimization based on usage patterns
2. Consider using mutable vectors for temporary state if immutability isn't required

## Expected Overall Impact

**Conservative Estimate**: 50-70% performance improvement (bringing TrackedProcessor to ~200-250ns per step)
**Optimistic Estimate**: 70-85% performance improvement (bringing TrackedProcessor to ~170-200ns per step)

The most impactful changes are likely:
1. **Optimized detailed usage structure** - replaces expensive Map operations with array access
2. **Bit vector memory tracking** - replaces expensive Set operations  
3. **String elimination** - removes allocation overhead

These three changes together could potentially reduce the performance gap from 2.57x to ~1.4-1.6x, making TrackedProcessor much more viable for performance-critical applications while maintaining its rich tracking capabilities.