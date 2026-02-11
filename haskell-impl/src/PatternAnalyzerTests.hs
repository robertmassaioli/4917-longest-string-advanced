{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}

module PatternAnalyzerTests
    ( runPatternAnalyzerTests
    , PatternAnalyzerTestResult(..)
    ) where

import PatternAnalyzer
import ProcessorTests (TestResult(..))
import ExecutionTracing (ProgramResult(..), TerminationType(..), ExecutionTrace(..), ExecutionState(..), TracePoint(..))
import Processor (Byte)
import WildcardPatterns (WildcardPattern(..), PatternElement(..), matchWildcardPattern)
import Data.Time (getCurrentTime, UTCTime)
import Data.Maybe (isJust, isNothing, fromJust)

-- | Result of a pattern analyzer test
data PatternAnalyzerTestResult = PatternAnalyzerTestResult
    { analyzerTestName :: String
    , analyzerTestPassed :: Bool
    , analyzerExpectedResult :: String
    , analyzerActualResult :: String
    , analyzerErrorMessage :: Maybe String
    } deriving (Show)

-- | Convert PatternAnalyzerTestResult to TestResult for integration
toTestResult :: PatternAnalyzerTestResult -> TestResult
toTestResult PatternAnalyzerTestResult{..} = TestResult
    { testName = analyzerTestName
    , testPassed = analyzerTestPassed
    , expectedResult = analyzerExpectedResult
    , actualResult = analyzerActualResult
    , errorMessage = analyzerErrorMessage
    }

-- | Run all pattern analyzer tests
runPatternAnalyzerTests :: IO [TestResult]
runPatternAnalyzerTests = do
    putStrLn "🔍 Running Pattern Analyzer Tests..."
    let allTests = concat
            [ patternTypeDetectionTests
            , loopAnalysisTests
            , confidenceScoringTests
            , wildcardGenerationTests
            , formulaGenerationTests
            , cycleDetectionTests
            , integrationTests
            ]
    
    results <- mapM runAnalyzerTest allTests
    let testResults = map toTestResult results
    
    putStrLn $ "  Completed " ++ show (length testResults) ++ " pattern analyzer tests"
    return testResults

-- | Run a single pattern analyzer test
runAnalyzerTest :: IO PatternAnalyzerTestResult -> IO PatternAnalyzerTestResult
runAnalyzerTest testAction = do
    result <- testAction
    putStrLn $ "    " ++ analyzerTestName result ++ if analyzerTestPassed result then " ✅" else " ❌"
    return result

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- | Create a sample execution trace for testing
createSampleTrace :: [Int] -> Int -> ExecutionTrace
createSampleTrace pcSequence steps =
    let -- Convert Int to Byte (Word8) and create trace points
        tracePointList = zipWith (\pc step -> 
            let state = ExecutionState 0 0 (fromIntegral pc) step 0 Nothing
            in StepTrace step state) pcSequence [0..]
        finalState = ExecutionState 0 0 (fromIntegral $ if null pcSequence then 0 else head pcSequence) steps 0 Nothing
    in ExecutionTrace tracePointList steps finalState

-- | Create a program result for testing
createTestProgramResult :: [Byte] -> Int -> Int -> TerminationType -> [Int] -> IO ProgramResult
createTestProgramResult program outputLen steps termType pcSequence = do
    timestamp <- getCurrentTime
    let trace = createSampleTrace pcSequence steps
    return ProgramResult
        { resultOutput = outputLen
        , resultSteps = steps
        , resultTermination = termType
        , resultTrace = trace
        , resultProgram = program
        , resultTimestamp = timestamp
        }

-- | Create a test that checks pattern properties
testPatternProperty :: String -> ProgramPattern -> (ProgramPattern -> Bool) -> String -> PatternAnalyzerTestResult
testPatternProperty testName pattern condition expectedDesc =
    let passed = condition pattern
        actualDesc = if passed then expectedDesc else "Condition failed"
    in PatternAnalyzerTestResult
        { analyzerTestName = testName
        , analyzerTestPassed = passed
        , analyzerExpectedResult = expectedDesc
        , analyzerActualResult = actualDesc
        , analyzerErrorMessage = if passed then Nothing else Just "Pattern property check failed"
        }

-- =============================================================================
-- TEST CASES
-- =============================================================================

-- | Pattern type detection tests
patternTypeDetectionTests :: [IO PatternAnalyzerTestResult]
patternTypeDetectionTests =
    [ testHaltPatternDetection
    , testSimpleLoopPatternDetection
    , testComplexLoopPatternDetection
    , testLinearPatternDetection
    ]

-- Test HALT pattern detection
testHaltPatternDetection :: IO PatternAnalyzerTestResult
testHaltPatternDetection = do
    let program = [8, 15, 0]  -- PRINT 15, HALT
    result <- createTestProgramResult program 2 5 Halt [0, 1, 2]
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "HALT Pattern Detection"
        pattern
        (\p -> patternType p == HaltPattern)
        "Should detect HaltPattern for programs that terminate with HALT"

-- Test simple loop pattern detection
testSimpleLoopPatternDetection :: IO PatternAnalyzerTestResult
testSimpleLoopPatternDetection = do
    let program = [8, 10, 13, 0]  -- PRINT 10, JMP 0
        pcSequence = [0, 1, 2, 0, 1, 2, 0, 1, 2]  -- Simple loop
    result <- createTestProgramResult program 0 100 InfiniteLoop pcSequence
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Simple Loop Pattern Detection"
        pattern
        (\p -> patternType p == SimpleLoopPattern)
        "Should detect SimpleLoopPattern for programs with infinite loops"

-- Test complex loop pattern detection
testComplexLoopPatternDetection :: IO PatternAnalyzerTestResult
testComplexLoopPatternDetection = do
    let program = [8, 15, 14, 5, 13, 0]  -- PRINT 15, JZ 5, JMP 0
        pcSequence = [0, 1, 2, 4, 0, 1, 2, 4]  -- Conditional loop
    result <- createTestProgramResult program 0 50 Timeout pcSequence
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Complex Loop Pattern Detection"
        pattern
        (\p -> patternType p == ComplexLoopPattern)
        "Should detect ComplexLoopPattern for conditional loops"

-- Test linear pattern detection
testLinearPatternDetection :: IO PatternAnalyzerTestResult
testLinearPatternDetection = do
    let program = [3, 4, 5, 6]  -- INC R0, INC R1, DEC R0, DEC R1
    result <- createTestProgramResult program 0 4 Error [0, 1, 2, 3]
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Linear Pattern Detection"
        pattern
        (\p -> patternType p == LinearPattern)
        "Should detect LinearPattern for programs with errors or simple sequences"

-- | Loop analysis tests
loopAnalysisTests :: [IO PatternAnalyzerTestResult]
loopAnalysisTests =
    [ testLoopStructureDetection
    , testLoopIterationCounting
    , testConditionalLoopDetection
    , testOutputPerIterationAnalysis
    ]

-- Test loop structure detection
testLoopStructureDetection :: IO PatternAnalyzerTestResult
testLoopStructureDetection = do
    let program = [8, 12, 13, 0]  -- PRINT 12, JMP 0
        pcSequence = [0, 1, 2, 0, 1, 2, 0, 1, 2]
    result <- createTestProgramResult program 0 30 InfiniteLoop pcSequence
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Loop Structure Detection"
        pattern
        (\p -> case patternLoop p of
            Just loop -> loopStart loop == 0 && loopEnd loop == 2
            Nothing -> False)
        "Should correctly identify loop start and end positions"

-- Test loop iteration counting
testLoopIterationCounting :: IO PatternAnalyzerTestResult
testLoopIterationCounting = do
    let program = [8, 5, 13, 0]  -- PRINT 5, JMP 0
        pcSequence = [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]  -- 4 iterations
    result <- createTestProgramResult program 0 40 Timeout pcSequence
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Loop Iteration Counting"
        pattern
        (\p -> case patternLoop p of
            Just loop -> loopIterations loop >= 3  -- Should detect multiple iterations
            Nothing -> False)
        "Should count the number of loop iterations from execution trace"

-- Test conditional loop detection
testConditionalLoopDetection :: IO PatternAnalyzerTestResult
testConditionalLoopDetection = do
    let program = [3, 14, 4, 13, 1]  -- INC R0, JZ 4, INC R1, JMP 1
        pcSequence = [0, 1, 2, 3, 1, 2, 3, 1, 4]  -- Conditional loop that eventually exits
    result <- createTestProgramResult program 0 25 Timeout pcSequence
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Conditional Loop Detection"
        pattern
        (\p -> case patternLoop p of
            Just loop -> isJust (loopCondition loop)
            Nothing -> False)
        "Should detect conditional loops and identify the condition instruction"

-- Test output per iteration analysis
testOutputPerIterationAnalysis :: IO PatternAnalyzerTestResult
testOutputPerIterationAnalysis = do
    let program = [8, 10, 8, 11, 13, 0]  -- PRINT 10, PRINT 11, JMP 0
        pcSequence = [0, 1, 2, 3, 4, 0, 1, 2, 3, 4]  -- 2 iterations with 4 chars output each
    result <- createTestProgramResult program 0 50 InfiniteLoop pcSequence
    let pattern = analyzeProgram program result
    
    return $ testPatternProperty
        "Output Per Iteration Analysis"
        pattern
        (\p -> case patternLoop p of
            Just loop -> outputPerIteration loop > 0  -- Should detect output production
            Nothing -> False)
        "Should analyze output produced per loop iteration"

-- | Confidence scoring tests
confidenceScoringTests :: [IO PatternAnalyzerTestResult]
confidenceScoringTests =
    [ testHaltPatternConfidence
    , testLoopPatternConfidence
    , testTraceQualityBonus
    , testConfidenceRange
    ]

-- Test HALT pattern confidence
testHaltPatternConfidence :: IO PatternAnalyzerTestResult
testHaltPatternConfidence = do
    let program = [8, 15, 0]
    result <- createTestProgramResult program 2 20 Halt [0, 1, 2]
    let pattern = analyzeProgram program result
        confidence = patternConfidenceScore pattern
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "HALT Pattern Confidence"
        , analyzerTestPassed = confidence >= 0.85
        , analyzerExpectedResult = "High confidence (>= 0.85) for HALT patterns"
        , analyzerActualResult = "Confidence: " ++ show confidence
        , analyzerErrorMessage = if confidence >= 0.85 then Nothing else Just "HALT patterns should have high confidence"
        }

-- Test loop pattern confidence
testLoopPatternConfidence :: IO PatternAnalyzerTestResult
testLoopPatternConfidence = do
    let program = [13, 0]  -- JMP 0
    result <- createTestProgramResult program 0 30 InfiniteLoop [0, 1, 0, 1, 0, 1]
    let pattern = analyzeProgram program result
        confidence = patternConfidenceScore pattern
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Loop Pattern Confidence"
        , analyzerTestPassed = confidence >= 0.75
        , analyzerExpectedResult = "Good confidence (>= 0.75) for loop patterns"
        , analyzerActualResult = "Confidence: " ++ show confidence
        , analyzerErrorMessage = if confidence >= 0.75 then Nothing else Just "Loop patterns should have good confidence"
        }

-- Test trace quality bonus
testTraceQualityBonus :: IO PatternAnalyzerTestResult
testTraceQualityBonus = do
    let program = [8, 15, 0]
    result1 <- createTestProgramResult program 2 5 Halt [0, 1, 2]    -- Short trace
    result2 <- createTestProgramResult program 2 25 Halt (replicate 25 0)  -- Long trace
    
    let pattern1 = analyzeProgram program result1
        pattern2 = analyzeProgram program result2
        confidence1 = patternConfidenceScore pattern1
        confidence2 = patternConfidenceScore pattern2
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Trace Quality Bonus"
        , analyzerTestPassed = confidence2 > confidence1
        , analyzerExpectedResult = "Longer traces should have higher confidence"
        , analyzerActualResult = "Short: " ++ show confidence1 ++ ", Long: " ++ show confidence2
        , analyzerErrorMessage = if confidence2 > confidence1 then Nothing else Just "Trace quality should affect confidence"
        }

-- Test confidence range
testConfidenceRange :: IO PatternAnalyzerTestResult
testConfidenceRange = do
    let program = [8, 15, 0]
    result <- createTestProgramResult program 2 10 Halt [0, 1, 2]
    let pattern = analyzeProgram program result
        confidence = patternConfidenceScore pattern
        inRange = confidence >= 0.1 && confidence <= 1.0
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Confidence Range"
        , analyzerTestPassed = inRange
        , analyzerExpectedResult = "Confidence should be between 0.1 and 1.0"
        , analyzerActualResult = "Confidence: " ++ show confidence
        , analyzerErrorMessage = if inRange then Nothing else Just "Confidence out of valid range"
        }

-- | Wildcard generation tests
wildcardGenerationTests :: [IO PatternAnalyzerTestResult]
wildcardGenerationTests =
    [ testWildcardGenerationForHalt
    , testWildcardGenerationForLoop
    , testNoWildcardForLinear
    , testWildcardPatternMatching
    ]

-- Test wildcard generation for HALT patterns
testWildcardGenerationForHalt :: IO PatternAnalyzerTestResult
testWildcardGenerationForHalt = do
    let program = [8, 15, 0]  -- PRINT 15, HALT
    result <- createTestProgramResult program 2 10 Halt [0, 1, 2]
    let pattern = analyzeProgram program result
        hasWildcard = isJust (patternWildcard pattern)
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Wildcard Generation for HALT"
        , analyzerTestPassed = hasWildcard
        , analyzerExpectedResult = "HALT patterns should generate wildcard templates"
        , analyzerActualResult = if hasWildcard then "Wildcard generated" else "No wildcard"
        , analyzerErrorMessage = if hasWildcard then Nothing else Just "HALT patterns should have wildcards"
        }

-- Test wildcard generation for loops
testWildcardGenerationForLoop :: IO PatternAnalyzerTestResult
testWildcardGenerationForLoop = do
    let program = [8, 10, 13, 0]  -- PRINT 10, JMP 0
    result <- createTestProgramResult program 0 30 InfiniteLoop [0, 1, 2, 0, 1, 2]
    let pattern = analyzeProgram program result
        hasWildcard = isJust (patternWildcard pattern)
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Wildcard Generation for Loop"
        , analyzerTestPassed = hasWildcard
        , analyzerExpectedResult = "Simple loop patterns should generate wildcards"
        , analyzerActualResult = if hasWildcard then "Wildcard generated" else "No wildcard"
        , analyzerErrorMessage = if hasWildcard then Nothing else Just "Loop patterns should have wildcards"
        }

-- Test no wildcard for linear patterns
testNoWildcardForLinear :: IO PatternAnalyzerTestResult
testNoWildcardForLinear = do
    let program = [3, 4, 5]  -- INC R0, INC R1, DEC R0
    result <- createTestProgramResult program 0 3 Error [0, 1, 2]
    let pattern = analyzeProgram program result
        hasWildcard = isJust (patternWildcard pattern)
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "No Wildcard for Linear"
        , analyzerTestPassed = not hasWildcard
        , analyzerExpectedResult = "Linear patterns should not generate wildcards"
        , analyzerActualResult = if hasWildcard then "Unexpected wildcard" else "No wildcard (correct)"
        , analyzerErrorMessage = if not hasWildcard then Nothing else Just "Linear patterns should not have wildcards"
        }

-- Test wildcard pattern matching
testWildcardPatternMatching :: IO PatternAnalyzerTestResult
testWildcardPatternMatching = do
    let program1 = [8, 15, 0]  -- PRINT 15, HALT
        program2 = [8, 12, 0]  -- PRINT 12, HALT (similar)
    result <- createTestProgramResult program1 2 10 Halt [0, 1, 2]
    let pattern = analyzeProgram program1 result
    
    case patternWildcard pattern of
        Nothing -> return PatternAnalyzerTestResult
            { analyzerTestName = "Wildcard Pattern Matching"
            , analyzerTestPassed = False
            , analyzerExpectedResult = "Pattern should have wildcard for matching test"
            , analyzerActualResult = "No wildcard generated"
            , analyzerErrorMessage = Just "Cannot test matching without wildcard"
            }
        Just wildcardPattern -> do
            let matches = case matchWildcardPattern program2 wildcardPattern of
                    Just _ -> True
                    Nothing -> False
            
            return PatternAnalyzerTestResult
                { analyzerTestName = "Wildcard Pattern Matching"
                , analyzerTestPassed = matches
                , analyzerExpectedResult = "Similar programs should match wildcard pattern"
                , analyzerActualResult = if matches then "Pattern matches" else "Pattern does not match"
                , analyzerErrorMessage = if matches then Nothing else Just "Wildcard should match similar programs"
                }

-- | Formula generation tests
formulaGenerationTests :: [IO PatternAnalyzerTestResult]
formulaGenerationTests =
    [ testOutputFormulaForHalt
    , testOutputFormulaForLoop
    , testStepsFormulaGeneration
    ]

-- Test output formula for HALT patterns
testOutputFormulaForHalt :: IO PatternAnalyzerTestResult
testOutputFormulaForHalt = do
    let program = [8, 15, 0]
    result <- createTestProgramResult program 2 10 Halt [0, 1, 2]
    let pattern = analyzeProgram program result
        formula = patternOutputFormula pattern
        isNumeric = all (\c -> c >= '0' && c <= '9') formula
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Output Formula for HALT"
        , analyzerTestPassed = isNumeric && formula == "2"
        , analyzerExpectedResult = "HALT patterns should have exact numeric output formula"
        , analyzerActualResult = "Formula: " ++ formula
        , analyzerErrorMessage = if isNumeric && formula == "2" then Nothing else Just "HALT formula should be exact output count"
        }

-- Test output formula for loops
testOutputFormulaForLoop :: IO PatternAnalyzerTestResult
testOutputFormulaForLoop = do
    let program = [8, 10, 13, 0]  -- PRINT 10, JMP 0
    result <- createTestProgramResult program 0 50 InfiniteLoop [0, 1, 2, 0, 1, 2]
    let pattern = analyzeProgram program result
        formula = patternOutputFormula pattern
        isInfinite = formula == "infinite"
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Output Formula for Loop"
        , analyzerTestPassed = isInfinite
        , analyzerExpectedResult = "Loop patterns should have 'infinite' output formula"
        , analyzerActualResult = "Formula: " ++ formula
        , analyzerErrorMessage = if isInfinite then Nothing else Just "Loop formula should indicate infinite output"
        }

-- Test steps formula generation
testStepsFormulaGeneration :: IO PatternAnalyzerTestResult
testStepsFormulaGeneration = do
    let program = [8, 15, 0]
    result <- createTestProgramResult program 2 15 Halt [0, 1, 2]
    let pattern = analyzeProgram program result
        formula = patternStepsFormula pattern
        isNumeric = all (\c -> c >= '0' && c <= '9') formula
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Steps Formula Generation"
        , analyzerTestPassed = isNumeric
        , analyzerExpectedResult = "Should generate numeric steps formula for HALT patterns"
        , analyzerActualResult = "Formula: " ++ formula
        , analyzerErrorMessage = if isNumeric then Nothing else Just "Steps formula should be numeric for HALT"
        }

-- | Cycle detection tests
cycleDetectionTests :: [IO PatternAnalyzerTestResult]
cycleDetectionTests =
    [ testSimpleCycleDetection
    , testNoCycleDetection
    , testComplexCycleDetection
    ]

-- Test simple cycle detection
testSimpleCycleDetection :: IO PatternAnalyzerTestResult
testSimpleCycleDetection = do
    let program = [13, 0]  -- JMP 0
        pcSequence = [0, 1, 0, 1, 0, 1, 0, 1]  -- Clear 2-instruction cycle
    result <- createTestProgramResult program 0 20 InfiniteLoop pcSequence
    let pattern = analyzeProgram program result
        hasLoop = isJust (patternLoop pattern)
        isSimpleLoop = patternType pattern == SimpleLoopPattern
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Simple Cycle Detection"
        , analyzerTestPassed = hasLoop && isSimpleLoop
        , analyzerExpectedResult = "Should detect simple cycles in execution trace"
        , analyzerActualResult = "Loop detected: " ++ show hasLoop ++ ", Type: " ++ show (patternType pattern)
        , analyzerErrorMessage = if hasLoop && isSimpleLoop then Nothing else Just "Failed to detect simple cycle"
        }

-- Test no cycle detection
testNoCycleDetection :: IO PatternAnalyzerTestResult
testNoCycleDetection = do
    let program = [8, 15, 8, 10, 0]  -- PRINT 15, PRINT 10, HALT
        pcSequence = [0, 1, 2, 3, 4]  -- Linear execution, no cycles
    result <- createTestProgramResult program 4 5 Halt pcSequence
    let pattern = analyzeProgram program result
        hasLoop = isJust (patternLoop pattern)
        isHaltPattern = patternType pattern == HaltPattern
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "No Cycle Detection"
        , analyzerTestPassed = not hasLoop && isHaltPattern
        , analyzerExpectedResult = "Should not detect cycles in linear execution"
        , analyzerActualResult = "Loop detected: " ++ show hasLoop ++ ", Type: " ++ show (patternType pattern)
        , analyzerErrorMessage = if not hasLoop && isHaltPattern then Nothing else Just "Incorrectly detected cycle in linear program"
        }

-- Test complex cycle detection
testComplexCycleDetection :: IO PatternAnalyzerTestResult
testComplexCycleDetection = do
    let program = [3, 15, 4, 13, 1]  -- INC R0, JNZ 4, INC R1, JMP 1
        -- Complex pattern: conditional jumps create irregular cycles
        pcSequence = [0, 1, 2, 3, 1, 2, 3, 1, 4]
    result <- createTestProgramResult program 0 30 Timeout pcSequence
    let pattern = analyzeProgram program result
        hasLoop = isJust (patternLoop pattern)
        isComplexLoop = patternType pattern == ComplexLoopPattern
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Complex Cycle Detection"
        , analyzerTestPassed = hasLoop && isComplexLoop
        , analyzerExpectedResult = "Should detect complex conditional cycles"
        , analyzerActualResult = "Loop detected: " ++ show hasLoop ++ ", Type: " ++ show (patternType pattern)
        , analyzerErrorMessage = if hasLoop && isComplexLoop then Nothing else Just "Failed to detect complex cycle pattern"
        }

-- | Integration tests
integrationTests :: [IO PatternAnalyzerTestResult]
integrationTests =
    [ testCompleteAnalysisWorkflow
    , testPatternConsistency
    ]

-- Test complete analysis workflow
testCompleteAnalysisWorkflow :: IO PatternAnalyzerTestResult
testCompleteAnalysisWorkflow = do
    let program = [8, 15, 8, 10, 0]  -- PRINT 15, PRINT 10, HALT
    result <- createTestProgramResult program 4 15 Halt [0, 1, 2, 3, 4]
    let pattern = analyzeProgram program result
        
        hasValidType = patternType pattern == HaltPattern
        hasValidConfidence = patternConfidenceScore pattern > 0.8
        hasValidFormula = patternOutputFormula pattern == "4"
        hasWildcard = isJust (patternWildcard pattern)
        
        allValid = hasValidType && hasValidConfidence && hasValidFormula && hasWildcard
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Complete Analysis Workflow"
        , analyzerTestPassed = allValid
        , analyzerExpectedResult = "All pattern components should be correctly analyzed"
        , analyzerActualResult = "Type: " ++ show (patternType pattern) ++
                               ", Confidence: " ++ show (patternConfidenceScore pattern) ++
                               ", Formula: " ++ patternOutputFormula pattern ++
                               ", Wildcard: " ++ show hasWildcard
        , analyzerErrorMessage = if allValid then Nothing else Just "Pattern analysis incomplete"
        }

-- Test pattern consistency
testPatternConsistency :: IO PatternAnalyzerTestResult
testPatternConsistency = do
    let program = [8, 12, 13, 0]  -- PRINT 12, JMP 0
    result1 <- createTestProgramResult program 0 25 InfiniteLoop [0, 1, 2, 0, 1, 2]
    result2 <- createTestProgramResult program 0 35 Timeout [0, 1, 2, 0, 1, 2, 0]
    
    let pattern1 = analyzeProgram program result1
        pattern2 = analyzeProgram program result2
        
        sameType = patternType pattern1 == patternType pattern2
        similarConfidence = abs (patternConfidenceScore pattern1 - patternConfidenceScore pattern2) < 0.2
        sameFormula = patternOutputFormula pattern1 == patternOutputFormula pattern2
        
        consistent = sameType && similarConfidence && sameFormula
    
    return PatternAnalyzerTestResult
        { analyzerTestName = "Pattern Consistency"
        , analyzerTestPassed = consistent
        , analyzerExpectedResult = "Same program should produce consistent patterns across different executions"
        , analyzerActualResult = "Type match: " ++ show sameType ++
                               ", Confidence diff: " ++ show (abs (patternConfidenceScore pattern1 - patternConfidenceScore pattern2)) ++
                               ", Formula match: " ++ show sameFormula
        , analyzerErrorMessage = if consistent then Nothing else Just "Pattern analysis should be consistent"
        }