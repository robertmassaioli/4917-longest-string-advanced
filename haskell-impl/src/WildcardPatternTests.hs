{-# LANGUAGE RecordWildCards #-}

module WildcardPatternTests
    ( runWildcardPatternTests
    , WildcardTestResult(..)
    ) where

import WildcardPatterns
import ProcessorTests (TestResult(..))
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Word (Word8)

-- | Result of a wildcard pattern test
data WildcardTestResult = WildcardTestResult
    { wildcardTestName :: String
    , wildcardTestPassed :: Bool
    , wildcardExpectedMatch :: Bool
    , wildcardActualMatch :: Bool
    , wildcardExpectedBindings :: Maybe (Map String Word8)
    , wildcardActualBindings :: Maybe (Map String Word8)
    , wildcardErrorMessage :: Maybe String
    } deriving (Show)

-- | Convert WildcardTestResult to TestResult for integration
toTestResult :: WildcardTestResult -> TestResult
toTestResult WildcardTestResult{..} = TestResult
    { testName = wildcardTestName
    , testPassed = wildcardTestPassed
    , expectedResult = show wildcardExpectedMatch ++ maybe "" (\b -> " with bindings " ++ show b) wildcardExpectedBindings
    , actualResult = show wildcardActualMatch ++ maybe "" (\b -> " with bindings " ++ show b) wildcardActualBindings
    , errorMessage = wildcardErrorMessage
    }

-- | Run all wildcard pattern tests
runWildcardPatternTests :: IO [TestResult]
runWildcardPatternTests = do
    putStrLn "🔍 Running Wildcard Pattern Tests..."
    let allTests = concat
            [ basicPatternTests
            , variableBindingTests
            , constraintTests
            , wildcardElementTests
            , programGeneralizationTests
            , edgeCaseTests
            ]
    
    results <- mapM runWildcardTest allTests
    let testResults = map toTestResult results
    
    putStrLn $ "  Completed " ++ show (length testResults) ++ " wildcard pattern tests"
    return testResults

-- | Run a single wildcard pattern test
runWildcardTest :: WildcardTestResult -> IO WildcardTestResult
runWildcardTest test = do
    putStrLn $ "    " ++ wildcardTestName test ++ if wildcardTestPassed test then " ✅" else " ❌"
    return test

-- =============================================================================
-- TEST CASES
-- =============================================================================

-- | Basic pattern matching tests
basicPatternTests :: [WildcardTestResult]
basicPatternTests =
    [ testFixedByteMatching
    , testFixedByteMismatch
    , testAnyByteMatching
    , testMixedPattern
    ]

-- Test exact byte matching
testFixedByteMatching :: WildcardTestResult
testFixedByteMatching = 
    let pattern = createWildcardPattern [FixedByte 8, FixedByte 15] [] "PRINT 15" 1.0
        program = [8, 15]
        result = matchWildcardPattern program pattern
        expected = Just Map.empty
    in WildcardTestResult
        { wildcardTestName = "Fixed Byte Matching"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Pattern should match exactly"
        }

-- Test byte mismatch
testFixedByteMismatch :: WildcardTestResult
testFixedByteMismatch = 
    let pattern = createWildcardPattern [FixedByte 8, FixedByte 15] [] "PRINT 15" 1.0
        program = [8, 14]  -- Different second byte
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "Fixed Byte Mismatch"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Pattern should not match"
        }

-- Test AnyByte wildcard
testAnyByteMatching :: WildcardTestResult
testAnyByteMatching = 
    let pattern = createWildcardPattern [FixedByte 8, AnyByte, FixedByte 0] [] "PRINT any, HALT" 0.8
        program = [8, 12, 0]  -- Any value for middle byte
        result = matchWildcardPattern program pattern
        expected = Just Map.empty
    in WildcardTestResult
        { wildcardTestName = "AnyByte Wildcard Matching"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "AnyByte should match any value"
        }

-- Test mixed pattern with multiple elements
testMixedPattern :: WildcardTestResult
testMixedPattern = 
    let pattern = createWildcardPattern 
            [FixedByte 8, AnyByte, FixedByte 13, AnyByte] 
            [] 
            "PRINT any, JMP any" 
            0.7
        program = [8, 15, 13, 2]
        result = matchWildcardPattern program pattern
        expected = Just Map.empty
    in WildcardTestResult
        { wildcardTestName = "Mixed Pattern Elements"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Mixed pattern should match"
        }

-- | Variable binding tests
variableBindingTests :: [WildcardTestResult]
variableBindingTests =
    [ testSimpleVariableBinding
    , testMultipleVariableBinding
    , testVariableConsistency
    , testVariableInconsistency
    ]

-- Test simple variable binding
testSimpleVariableBinding :: WildcardTestResult
testSimpleVariableBinding = 
    let pattern = createWildcardPattern [FixedByte 8, Variable "value"] [] "PRINT value" 0.9
        program = [8, 15]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("value", 15)])
    in WildcardTestResult
        { wildcardTestName = "Simple Variable Binding"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Should bind variable 'value' to 15"
        }

-- Test multiple variable bindings
testMultipleVariableBinding :: WildcardTestResult
testMultipleVariableBinding = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val1", FixedByte 8, Variable "val2"] 
            [] 
            "PRINT val1, PRINT val2" 
            0.8
        program = [8, 15, 8, 10]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("val1", 15), ("val2", 10)])
    in WildcardTestResult
        { wildcardTestName = "Multiple Variable Binding"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Should bind both variables correctly"
        }

-- Test variable consistency (same variable used twice)
testVariableConsistency :: WildcardTestResult
testVariableConsistency = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val", FixedByte 8, Variable "val"] 
            [] 
            "PRINT val twice" 
            0.9
        program = [8, 12, 8, 12]  -- Same value twice
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("val", 12)])
    in WildcardTestResult
        { wildcardTestName = "Variable Consistency"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Same variable should bind to same value"
        }

-- Test variable inconsistency (should fail)
testVariableInconsistency :: WildcardTestResult
testVariableInconsistency = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val", FixedByte 8, Variable "val"] 
            [] 
            "PRINT val twice" 
            0.9
        program = [8, 12, 8, 15]  -- Different values
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "Variable Inconsistency"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Same variable with different values should fail"
        }

-- | Constraint evaluation tests
constraintTests :: [WildcardTestResult]
constraintTests =
    [ testEqualConstraint
    , testNotEqualConstraint
    , testInRangeConstraint
    , testInRangeConstraintFail
    , testSameAsConstraint
    , testDifferentFromConstraint
    ]

-- Test Equal constraint
testEqualConstraint :: WildcardTestResult
testEqualConstraint = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val"] 
            [Equal "val" 15] 
            "PRINT 15 only" 
            0.95
        program = [8, 15]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("val", 15)])
    in WildcardTestResult
        { wildcardTestName = "Equal Constraint"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Equal constraint should pass for correct value"
        }

-- Test NotEqual constraint
testNotEqualConstraint :: WildcardTestResult
testNotEqualConstraint = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val"] 
            [NotEqual "val" 0] 
            "PRINT non-zero" 
            0.8
        program = [8, 15]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("val", 15)])
    in WildcardTestResult
        { wildcardTestName = "NotEqual Constraint"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "NotEqual constraint should pass for different value"
        }

-- Test InRange constraint (pass)
testInRangeConstraint :: WildcardTestResult
testInRangeConstraint = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val"] 
            [InRange "val" 10 15] 
            "PRINT 10-15" 
            0.8
        program = [8, 12]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("val", 12)])
    in WildcardTestResult
        { wildcardTestName = "InRange Constraint (pass)"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "InRange constraint should pass for value in range"
        }

-- Test InRange constraint (fail)
testInRangeConstraintFail :: WildcardTestResult
testInRangeConstraintFail = 
    let pattern = createWildcardPattern 
            [FixedByte 8, Variable "val"] 
            [InRange "val" 10 15] 
            "PRINT 10-15" 
            0.8
        program = [8, 5]  -- Outside range
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "InRange Constraint (fail)"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "InRange constraint should fail for value outside range"
        }

-- Test SameAs constraint
testSameAsConstraint :: WildcardTestResult
testSameAsConstraint = 
    let pattern = createWildcardPattern 
            [Variable "addr1", Variable "addr2"] 
            [SameAs "addr1" "addr2"] 
            "Same addresses" 
            0.7
        program = [5, 5]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("addr1", 5), ("addr2", 5)])
    in WildcardTestResult
        { wildcardTestName = "SameAs Constraint"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "SameAs constraint should pass for equal values"
        }

-- Test DifferentFrom constraint
testDifferentFromConstraint :: WildcardTestResult
testDifferentFromConstraint = 
    let pattern = createWildcardPattern 
            [Variable "addr1", Variable "addr2"] 
            [DifferentFrom "addr1" "addr2"] 
            "Different addresses" 
            0.7
        program = [3, 7]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("addr1", 3), ("addr2", 7)])
    in WildcardTestResult
        { wildcardTestName = "DifferentFrom Constraint"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "DifferentFrom constraint should pass for different values"
        }

-- | Wildcard element tests
wildcardElementTests :: [WildcardTestResult]
wildcardElementTests =
    [ testInstructionWildcard
    , testInstructionWildcardFail
    , testAddressWildcard
    , testAddressWildcardFail
    ]

-- Test InstructionWildcard (valid instruction)
testInstructionWildcard :: WildcardTestResult
testInstructionWildcard = 
    let pattern = createWildcardPattern [InstructionWildcard, FixedByte 5] [] "Any instruction with operand 5" 0.6
        program = [13, 5]  -- JMP 5
        result = matchWildcardPattern program pattern
        expected = Just Map.empty
    in WildcardTestResult
        { wildcardTestName = "InstructionWildcard (valid)"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "InstructionWildcard should match valid instruction"
        }

-- Test InstructionWildcard (invalid instruction)
testInstructionWildcardFail :: WildcardTestResult
testInstructionWildcardFail = 
    let pattern = createWildcardPattern [InstructionWildcard] [] "Any instruction" 0.5
        program = [16]  -- Invalid instruction > 15
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "InstructionWildcard (invalid)"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "InstructionWildcard should reject invalid instruction"
        }

-- Test AddressWildcard (valid address)
testAddressWildcard :: WildcardTestResult
testAddressWildcard = 
    let pattern = createWildcardPattern [FixedByte 9, AddressWildcard] [] "LOAD R0 from any address" 0.7
        program = [9, 12]  -- LOAD R0, 12
        result = matchWildcardPattern program pattern
        expected = Just Map.empty
    in WildcardTestResult
        { wildcardTestName = "AddressWildcard (valid)"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "AddressWildcard should match valid address"
        }

-- Test AddressWildcard (invalid address)
testAddressWildcardFail :: WildcardTestResult
testAddressWildcardFail = 
    let pattern = createWildcardPattern [FixedByte 9, AddressWildcard] [] "LOAD R0 from any address" 0.7
        program = [9, 16]  -- Invalid address > 15
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "AddressWildcard (invalid)"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "AddressWildcard should reject invalid address"
        }

-- | Program generalization tests
programGeneralizationTests :: [WildcardTestResult]
programGeneralizationTests =
    [ testWildcardFromProgram
    , testGeneralizationConfidence
    ]

-- Test wildcardFromProgram function
testWildcardFromProgram :: WildcardTestResult
testWildcardFromProgram = 
    let program = [8, 15, 0]  -- PRINT 15, HALT
        generatedPattern = wildcardFromProgram program "Generated pattern"
        -- Test that it can match the original program
        result = matchWildcardPattern program generatedPattern
        expected = case result of
            Just _ -> True
            Nothing -> False
    in WildcardTestResult
        { wildcardTestName = "wildcardFromProgram"
        , wildcardTestPassed = expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = expected
        , wildcardExpectedBindings = Nothing
        , wildcardActualBindings = result
        , wildcardErrorMessage = if expected then Nothing else Just "Generated pattern should match original program"
        }

-- Test generalization confidence
testGeneralizationConfidence :: WildcardTestResult
testGeneralizationConfidence = 
    let program = [8, 15, 0]
        generatedPattern = wildcardFromProgram program "Test confidence"
        confidence = wildcardConfidence generatedPattern
        expected = confidence >= 0.3 && confidence <= 0.9
    in WildcardTestResult
        { wildcardTestName = "Generalization Confidence"
        , wildcardTestPassed = expected
        , wildcardExpectedMatch = expected
        , wildcardActualMatch = expected
        , wildcardExpectedBindings = Nothing
        , wildcardActualBindings = Nothing
        , wildcardErrorMessage = if expected then Nothing else Just $ "Confidence should be between 0.3 and 0.9, got " ++ show confidence
        }

-- | Edge case tests
edgeCaseTests :: [WildcardTestResult]
edgeCaseTests =
    [ testEmptyPattern
    , testEmptyProgram
    , testLengthMismatch
    , testComplexPattern
    ]

-- Test empty pattern
testEmptyPattern :: WildcardTestResult
testEmptyPattern = 
    let pattern = createWildcardPattern [] [] "Empty pattern" 1.0
        program = []
        result = matchWildcardPattern program pattern
        expected = Just Map.empty
    in WildcardTestResult
        { wildcardTestName = "Empty Pattern"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Empty pattern should match empty program"
        }

-- Test empty program
testEmptyProgram :: WildcardTestResult
testEmptyProgram = 
    let pattern = createWildcardPattern [FixedByte 8] [] "Non-empty pattern" 1.0
        program = []
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "Empty Program"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Non-empty pattern should not match empty program"
        }

-- Test length mismatch
testLengthMismatch :: WildcardTestResult
testLengthMismatch = 
    let pattern = createWildcardPattern [FixedByte 8, FixedByte 15] [] "Two bytes" 1.0
        program = [8, 15, 0]  -- Three bytes
        result = matchWildcardPattern program pattern
        expected = Nothing
    in WildcardTestResult
        { wildcardTestName = "Length Mismatch"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = False
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Different length pattern should not match"
        }

-- Test complex pattern with multiple constraints
testComplexPattern :: WildcardTestResult
testComplexPattern = 
    let pattern = createWildcardPattern 
            [ FixedByte 8, Variable "val1"    -- PRINT val1
            , FixedByte 8, Variable "val2"    -- PRINT val2  
            , FixedByte 13, Variable "addr"   -- JMP addr
            ] 
            [ InRange "val1" 10 15
            , InRange "val2" 0 9
            , Equal "addr" 0
            , DifferentFrom "val1" "val2"
            ] 
            "Complex pattern" 
            0.6
        program = [8, 15, 8, 5, 13, 0]
        result = matchWildcardPattern program pattern
        expected = Just (Map.fromList [("val1", 15), ("val2", 5), ("addr", 0)])
    in WildcardTestResult
        { wildcardTestName = "Complex Pattern with Multiple Constraints"
        , wildcardTestPassed = result == expected
        , wildcardExpectedMatch = True
        , wildcardActualMatch = case result of Just _ -> True; Nothing -> False
        , wildcardExpectedBindings = expected
        , wildcardActualBindings = result
        , wildcardErrorMessage = if result == expected then Nothing else Just "Complex pattern with constraints should match correctly"
        }