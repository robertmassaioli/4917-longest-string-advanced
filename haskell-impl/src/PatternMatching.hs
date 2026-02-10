module PatternMatching
    ( PatternMatcher(..)
    , SimplePatternMatcher(..)
    , createSimplePatternMatcher
    , matchPattern
    , generateBasicPatterns
    , patternFromResult
    ) where

import ExecutionTracing (ProgramResult(..), TerminationType(..))
import PatternCache (PatternResult(..), PatternEntry(..))
import Processor (Byte)
import Data.Time (getCurrentTime)
import qualified Data.Map as Map
import Data.Map (Map)
import Data.List (isPrefixOf)

-- | Pattern matching interface
class PatternMatcher m where
    -- | Check if a program matches any known patterns
    findMatch :: m -> [Byte] -> Maybe PatternResult
    
    -- | Add a new pattern from a program result  
    addPattern :: m -> [Byte] -> ProgramResult -> IO m
    
    -- | Get statistics about the matcher
    getMatcherStats :: m -> (Int, Double)  -- (patterns, hit_rate)

-- | Simple pattern matcher using exact program matching
data SimplePatternMatcher = SimplePatternMatcher
    { exactPatterns :: Map [Byte] PatternResult
    , lookupCount :: Int
    , hitCount :: Int
    } deriving (Show, Eq)

instance PatternMatcher SimplePatternMatcher where
    findMatch matcher program = Map.lookup program (exactPatterns matcher)
    
    addPattern matcher program result = do
        let patternResult = patternFromResult result
            newPatterns = Map.insert program patternResult (exactPatterns matcher)
        return matcher { exactPatterns = newPatterns }
    
    getMatcherStats matcher = 
        let totalLookups = lookupCount matcher
            hits = hitCount matcher
            hitRate = if totalLookups > 0 
                     then fromIntegral hits / fromIntegral totalLookups 
                     else 0.0
            patternCount = Map.size (exactPatterns matcher)
        in (patternCount, hitRate)

-- | Create a new simple pattern matcher
createSimplePatternMatcher :: SimplePatternMatcher
createSimplePatternMatcher = SimplePatternMatcher Map.empty 0 0

-- | Match a program against patterns and update statistics
matchPattern :: SimplePatternMatcher -> [Byte] -> (Maybe PatternResult, SimplePatternMatcher)
matchPattern matcher program = 
    case Map.lookup program (exactPatterns matcher) of
        Nothing -> 
            let updatedMatcher = matcher { lookupCount = lookupCount matcher + 1 }
            in (Nothing, updatedMatcher)
        Just result ->
            let updatedMatcher = matcher 
                    { lookupCount = lookupCount matcher + 1
                    , hitCount = hitCount matcher + 1
                    }
            in (Just result, updatedMatcher)

-- | Convert ProgramResult to PatternResult
patternFromResult :: ProgramResult -> PatternResult
patternFromResult result = PatternResult
    { patternOutput = resultOutput result
    , patternSteps = resultSteps result
    , patternTermination = resultTermination result
    , patternConfidence = 1.0
    }

-- | Generate basic patterns from a set of program results
generateBasicPatterns :: [([Byte], ProgramResult)] -> [(String, PatternResult)]
generateBasicPatterns programResults = 
    let groupedResults = groupByResult programResults
        patterns = concatMap createPatternsFromGroup groupedResults
    in patterns
  where
    -- Group programs by their results
    groupByResult :: [([Byte], ProgramResult)] -> [([([Byte], ProgramResult)], PatternResult)]
    groupByResult results = 
        let resultGroups = Map.toList $ Map.fromListWith (++) 
                [(patternFromResult result, [(program, result)]) | (program, result) <- results]
        in [(programs, patternResult) | (patternResult, programs) <- resultGroups]
    
    -- Create patterns from a group of programs with the same result
    createPatternsFromGroup :: ([([Byte], ProgramResult)], PatternResult) -> [(String, PatternResult)]
    createPatternsFromGroup (programs, result)
        | length programs < 2 = []  -- Need at least 2 programs to create a pattern
        | otherwise = 
            let patterns = findCommonPatterns (map fst programs)
            in [(pattern, result) | pattern <- patterns]

-- | Find common patterns in a list of programs
findCommonPatterns :: [[Byte]] -> [String]
findCommonPatterns programs
    | length programs < 2 = []
    | otherwise = 
        let haltPatterns = findHaltPatterns programs
            loopPatterns = findLoopPatterns programs
            prefixPatterns = findPrefixPatterns programs
        in haltPatterns ++ loopPatterns ++ prefixPatterns

-- | Find HALT-based patterns (instructions after HALT are irrelevant)
findHaltPatterns :: [[Byte]] -> [String]
findHaltPatterns programs = 
    let haltPrograms = [takeWhile (/= 0) prog ++ [0] | prog <- programs, 0 `elem` prog]
        commonHaltPatterns = findExactMatches haltPrograms
    in ["HALT:" ++ show pattern | pattern <- commonHaltPatterns, length pattern <= 6]

-- | Find loop-based patterns  
findLoopPatterns :: [[Byte]] -> [String]
findLoopPatterns programs =
    let simpleLoops = [prog | prog <- programs, isSimpleLoop prog]
        loopPatterns = findExactMatches simpleLoops
    in ["LOOP:" ++ show pattern | pattern <- loopPatterns, length pattern <= 4]
  where
    isSimpleLoop :: [Byte] -> Bool
    isSimpleLoop prog = case prog of
        (13:0:_) -> True  -- JMP 0
        _ -> False

-- | Find common prefixes
findPrefixPatterns :: [[Byte]] -> [String]
findPrefixPatterns programs = 
    let prefixes = [take n prog | prog <- programs, n <- [2..4], length prog >= n]
        commonPrefixes = findExactMatches prefixes
    in ["PREFIX:" ++ show pattern | pattern <- commonPrefixes, length pattern >= 2]

-- | Find exact matches in a list of patterns
findExactMatches :: (Eq a, Show a, Ord a) => [a] -> [a]
findExactMatches patterns = 
    let counted = Map.toList $ Map.fromListWith (+) [(pattern, 1) | pattern <- patterns]
        frequent = [pattern | (pattern, count) <- counted, count >= 2]
    in frequent

-- | Advanced pattern matching with wildcards (future extension)
data WildcardPattern = WildcardPattern
    { patternTemplate :: [PatternElement]
    , patternConstraints :: Map String (Byte -> Bool)
    , expectedResult :: PatternResult
    }

data PatternElement 
    = Literal Byte           -- Exact value
    | Wildcard String        -- Named wildcard
    | AnyValue              -- Any value accepted
    deriving (Show, Eq)

-- | Match program against wildcard pattern (future implementation)
matchWildcardPattern :: WildcardPattern -> [Byte] -> Maybe (Map String Byte)
matchWildcardPattern pattern program = 
    case zipMatch program (patternTemplate pattern) of
        Nothing -> Nothing
        Just bindings -> 
            if all (\(name, value) -> 
                case Map.lookup name (patternConstraints pattern) of
                    Nothing -> True
                    Just constraint -> constraint value
                ) (Map.toList bindings)
            then Just bindings
            else Nothing
  where
    zipMatch :: [Byte] -> [PatternElement] -> Maybe (Map String Byte)
    zipMatch [] [] = Just Map.empty
    zipMatch (b:bs) (Literal v:ps) 
        | b == v = zipMatch bs ps
        | otherwise = Nothing
    zipMatch (b:bs) (Wildcard name:ps) = 
        case zipMatch bs ps of
            Nothing -> Nothing  
            Just bindings -> Just (Map.insert name b bindings)
    zipMatch (b:bs) (AnyValue:ps) = zipMatch bs ps
    zipMatch _ _ = Nothing  -- Length mismatch

-- | Example patterns for common cases
commonPatterns :: [WildcardPattern]
commonPatterns = 
    [ -- PRINT x, HALT pattern
      WildcardPattern 
        { patternTemplate = [Literal 8, Wildcard "value", Literal 0]
        , patternConstraints = Map.fromList [("value", \v -> v <= 15)]
        , expectedResult = PatternResult 8 2 Halt 0.9
        }
    , -- Simple infinite loop
      WildcardPattern
        { patternTemplate = [Literal 13, Literal 0] 
        , patternConstraints = Map.empty
        , expectedResult = PatternResult 0 0 InfiniteLoop 1.0
        }
    ]