{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module PatternAnalyzer
    ( ProgramPattern(..)
    , PatternType(..)
    , LoopPattern(..)
    , analyzeProgram
    , detectHaltPattern
    , detectLoopPattern
    , generatePattern
    , matchesPattern
    , patternConfidence
    ) where

import ExecutionTracing (ProgramResult(..), TerminationType(..), ExecutionStep(..), extractExecutionSteps)
import Processor (Byte)
import Data.List (isPrefixOf, findIndex, nub)
import Control.DeepSeq (NFData, rnf)
import GHC.Generics (Generic)

-- | Types of patterns we can detect
data PatternType
    = HaltPattern       -- Program definitely halts
    | SimpleLoopPattern -- Simple infinite loop detected
    | ComplexLoopPattern -- Complex loop with conditions
    | LinearPattern     -- No loops, straight execution
    deriving (Show, Eq, Ord, Generic)

instance NFData PatternType

-- | Loop pattern structure
data LoopPattern = LoopPattern
    { loopStart :: Int          -- Starting instruction address
    , loopEnd :: Int            -- Ending instruction address  
    , loopCondition :: Maybe Byte -- Loop condition if conditional
    , loopIterations :: Int     -- Number of iterations observed
    , outputPerIteration :: Int -- Output produced per iteration
    } deriving (Show, Eq, Generic)

instance NFData LoopPattern

-- | A detected program pattern
data ProgramPattern = ProgramPattern
    { patternProgram :: [Byte]      -- The original program
    , patternType :: PatternType    -- Type of pattern detected
    , patternLoop :: Maybe LoopPattern -- Loop details if applicable
    , patternOutputFormula :: String  -- Formula for computing output
    , patternStepsFormula :: String   -- Formula for computing steps
    , patternConfidenceScore :: Double -- How confident we are (0.0-1.0)
    } deriving (Show, Eq, Generic)

instance NFData ProgramPattern

-- | Analyze a program execution and detect patterns
analyzeProgram :: [Byte] -> ProgramResult -> ProgramPattern
analyzeProgram program result = 
    let patternType = detectPatternType result
        loopPattern = detectLoopPattern result
        confidence = patternConfidence result patternType
    in ProgramPattern
        { patternProgram = program
        , patternType = patternType
        , patternLoop = loopPattern
        , patternOutputFormula = generateOutputFormula result patternType loopPattern
        , patternStepsFormula = generateStepsFormula result patternType loopPattern
        , patternConfidenceScore = confidence
        }

-- | Detect the primary pattern type from execution result
detectPatternType :: ProgramResult -> PatternType
detectPatternType result = 
    case resultTermination result of
        Halt -> HaltPattern
        InfiniteLoop -> detectLoopComplexity (extractExecutionSteps result)
        Timeout -> detectLoopComplexity (extractExecutionSteps result)
        ExecutionTracing.Error -> LinearPattern

-- | Distinguish between simple and complex loops
detectLoopComplexity :: [ExecutionStep] -> PatternType
detectLoopComplexity trace =
    let cycles = detectCycles trace
    in if not (null cycles) && length (head cycles) <= 3
       then SimpleLoopPattern
       else ComplexLoopPattern

-- | Detect HALT pattern - programs that definitely terminate
detectHaltPattern :: [Byte] -> ProgramResult -> Bool
detectHaltPattern program ProgramResult{..} = 
    case resultTermination of
        Halt -> True
        _ -> hasObviousHalt program

-- | Check if program has obvious HALT instruction that will be reached
hasObviousHalt :: [Byte] -> Bool
hasObviousHalt program = 
    let haltPositions = findHaltInstructions program
        reachablePositions = findReachableInstructions program
    in any (`elem` reachablePositions) haltPositions
  where
    findHaltInstructions prog = [i | (i, instr) <- zip [0..] prog, instr == 0]
    
    -- Simplified reachability analysis - just linear execution for now
    findReachableInstructions prog = [0..length prog - 1]

-- | Detect loop pattern from execution trace
detectLoopPattern :: ProgramResult -> Maybe LoopPattern
detectLoopPattern result = 
    case resultTermination result of
        InfiniteLoop -> analyzeLoopStructure (extractExecutionSteps result)
        Timeout -> analyzeLoopStructure (extractExecutionSteps result)
        _ -> Nothing

-- | Analyze trace to find loop structure
analyzeLoopStructure :: [ExecutionStep] -> Maybe LoopPattern
analyzeLoopStructure trace
    | length trace < 10 = Nothing  -- Need sufficient trace
    | otherwise = 
        let cycles = detectCycles trace
            outputPattern = analyzeOutputPattern trace
        in case cycles of
            [] -> Nothing
            (cycle:_) -> Just $ LoopPattern
                { loopStart = minimum [stepProgramCounter step | step <- cycle]
                , loopEnd = maximum [stepProgramCounter step | step <- cycle]
                , loopCondition = detectLoopCondition cycle
                , loopIterations = countIterations trace cycle
                , outputPerIteration = outputPerLoop cycle outputPattern
                }

-- | Detect repeated cycles in execution trace
detectCycles :: [ExecutionStep] -> [[ExecutionStep]]
detectCycles trace = 
    let positions = map stepProgramCounter trace
        cycleLength = findCycleLength positions
    in if cycleLength > 0
       then [take cycleLength $ drop (length trace - cycleLength * 2) trace]
       else []

-- | Find length of repeating cycle in program counter sequence
findCycleLength :: [Int] -> Int
findCycleLength positions
    | length positions < 20 = 0  -- Need enough data
    | otherwise = 
        let halfLength = length positions `div` 2
            firstHalf = take halfLength positions
            secondHalf = drop halfLength positions
            commonPrefix = length $ takeWhile id $ zipWith (==) (reverse firstHalf) (reverse secondHalf)
        in if commonPrefix >= 3 then commonPrefix else 0

-- | Detect what condition controls the loop
detectLoopCondition :: [ExecutionStep] -> Maybe Byte
detectLoopCondition cycle = 
    -- Look for conditional jump instructions (14, 15)
    case [instr | step <- cycle, let instr = stepInstruction step, instr `elem` [14, 15]] of
        [] -> Nothing  -- Unconditional loop
        (instr:_) -> Just instr  -- First conditional instruction found

-- | Count how many iterations of the cycle we observed
countIterations :: [ExecutionStep] -> [ExecutionStep] -> Int
countIterations trace cycle = 
    let cycleLength = length cycle
        traceLength = length trace
    in if cycleLength > 0 
       then traceLength `div` cycleLength
       else 1

-- | Analyze output pattern in the trace
analyzeOutputPattern :: [ExecutionStep] -> [Int]
analyzeOutputPattern trace = 
    [stepOutput step | step <- trace, stepOutput step > 0]

-- | Calculate output per loop iteration
outputPerLoop :: [ExecutionStep] -> [Int] -> Int
outputPerLoop cycle outputPattern = 
    let cycleOutputs = [stepOutput step | step <- cycle, stepOutput step > 0]
        totalCycleOutput = sum cycleOutputs
    in totalCycleOutput

-- | Generate formula for computing output based on pattern
generateOutputFormula :: ProgramResult -> PatternType -> Maybe LoopPattern -> String
generateOutputFormula result patternType loopPattern = 
    case patternType of
        HaltPattern -> show (resultOutput result)
        LinearPattern -> show (resultOutput result)
        SimpleLoopPattern -> 
            case loopPattern of
                Nothing -> "infinite"
                Just loop -> if outputPerIteration loop > 0 
                           then "infinite"  -- Infinite output
                           else "0"         -- No output in loop
        ComplexLoopPattern -> "complex_formula"  -- TODO: More sophisticated analysis

-- | Generate formula for computing steps based on pattern
generateStepsFormula :: ProgramResult -> PatternType -> Maybe LoopPattern -> String
generateStepsFormula result patternType loopPattern = 
    case patternType of
        HaltPattern -> show (resultSteps result)
        LinearPattern -> show (resultSteps result)
        SimpleLoopPattern -> "infinite"
        ComplexLoopPattern -> "complex_steps"

-- | Calculate confidence in pattern detection (0.0 to 1.0)
patternConfidence :: ProgramResult -> PatternType -> Double
patternConfidence result patternType = 
    let baseConfidence = case patternType of
            HaltPattern -> 0.95  -- Very confident for HALT
            SimpleLoopPattern -> 0.85  -- High confidence for simple loops
            LinearPattern -> 0.80  -- Good confidence for linear
            ComplexLoopPattern -> 0.60  -- Lower confidence for complex patterns
        
        -- Adjust based on trace length and consistency
        traceSteps = extractExecutionSteps result
        traceBonus = min 0.1 (fromIntegral (length traceSteps) / 1000.0)
        
        -- Penalty for very short traces
        tracePenalty = if length traceSteps < 10 then 0.2 else 0.0
        
    in max 0.1 $ min 1.0 $ baseConfidence + traceBonus - tracePenalty

-- | Generate a reusable pattern from a specific program analysis
generatePattern :: [Byte] -> ProgramResult -> ProgramPattern
generatePattern = analyzeProgram

-- | Check if a program matches an existing pattern
matchesPattern :: [Byte] -> ProgramPattern -> Bool
matchesPattern program pattern = 
    -- For Phase 2, we do exact matching
    -- Phase 3 will add wildcard and constraint-based matching
    program == patternProgram pattern

-- Note: stepInstruction, stepProgramCounter, and stepOutput are now 
-- direct field accessors from the ExecutionStep record, so no helper functions needed.