module LegacyWildcardPatternsSpec (spec) where

import Test.Hspec
import Test.Hspec.QuickCheck
import LegacyWildcardPatterns
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Word (Word8)

spec :: Spec
spec = describe "Wildcard Patterns" $ do
  context "Basic Pattern Matching" $ do
    it "Fixed Byte Matching" $ do
      let pattern = createWildcardPattern [FixedByte 8, FixedByte 15] [] "PRINT 15" 1.0
          program = [8, 15]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just Map.empty

    it "Fixed Byte Mismatch" $ do
      let pattern = createWildcardPattern [FixedByte 8, FixedByte 15] [] "PRINT 15" 1.0
          program = [8, 14]  -- Different second byte
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

    it "AnyByte Wildcard Matching" $ do
      let pattern = createWildcardPattern [FixedByte 8, AnyByte, FixedByte 0] [] "PRINT any, HALT" 0.8
          program = [8, 12, 0]  -- Any value for middle byte
          result = matchWildcardPattern program pattern
      result `shouldBe` Just Map.empty

    it "Mixed Pattern Elements" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, AnyByte, FixedByte 13, AnyByte] 
              [] 
              "PRINT any, JMP any" 
              0.7
          program = [8, 15, 13, 2]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just Map.empty

  context "Variable Binding" $ do
    it "Simple Variable Binding" $ do
      let pattern = createWildcardPattern [FixedByte 8, Variable "value"] [] "PRINT value" 0.9
          program = [8, 15]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("value", 15)])

    it "Multiple Variable Binding" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val1", FixedByte 8, Variable "val2"] 
              [] 
              "PRINT val1, PRINT val2" 
              0.8
          program = [8, 15, 8, 10]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("val1", 15), ("val2", 10)])

    it "Variable Consistency" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val", FixedByte 8, Variable "val"] 
              [] 
              "PRINT val twice" 
              0.9
          program = [8, 12, 8, 12]  -- Same value twice
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("val", 12)])

    it "Variable Inconsistency" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val", FixedByte 8, Variable "val"] 
              [] 
              "PRINT val twice" 
              0.9
          program = [8, 12, 8, 15]  -- Different values
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

  context "Constraint Evaluation" $ do
    it "Equal Constraint" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val"] 
              [Equal "val" 15] 
              "PRINT 15 only" 
              0.95
          program = [8, 15]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("val", 15)])

    it "NotEqual Constraint" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val"] 
              [NotEqual "val" 0] 
              "PRINT non-zero" 
              0.8
          program = [8, 15]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("val", 15)])

    it "InRange Constraint (pass)" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val"] 
              [InRange "val" 10 15] 
              "PRINT 10-15" 
              0.8
          program = [8, 12]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("val", 12)])

    it "InRange Constraint (fail)" $ do
      let pattern = createWildcardPattern 
              [FixedByte 8, Variable "val"] 
              [InRange "val" 10 15] 
              "PRINT 10-15" 
              0.8
          program = [8, 5]  -- Outside range
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

    it "SameAs Constraint" $ do
      let pattern = createWildcardPattern 
              [Variable "addr1", Variable "addr2"] 
              [SameAs "addr1" "addr2"] 
              "Same addresses" 
              0.7
          program = [5, 5]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("addr1", 5), ("addr2", 5)])

    it "DifferentFrom Constraint" $ do
      let pattern = createWildcardPattern 
              [Variable "addr1", Variable "addr2"] 
              [DifferentFrom "addr1" "addr2"] 
              "Different addresses" 
              0.7
          program = [3, 7]
          result = matchWildcardPattern program pattern
      result `shouldBe` Just (Map.fromList [("addr1", 3), ("addr2", 7)])

  context "Wildcard Elements" $ do
    it "InstructionWildcard (valid)" $ do
      let pattern = createWildcardPattern [InstructionWildcard, FixedByte 5] [] "Any instruction with operand 5" 0.6
          program = [13, 5]  -- JMP 5
          result = matchWildcardPattern program pattern
      result `shouldBe` Just Map.empty

    it "InstructionWildcard (invalid)" $ do
      let pattern = createWildcardPattern [InstructionWildcard] [] "Any instruction" 0.5
          program = [16]  -- Invalid instruction > 15
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

    it "AddressWildcard (valid)" $ do
      let pattern = createWildcardPattern [FixedByte 9, AddressWildcard] [] "LOAD R0 from any address" 0.7
          program = [9, 12]  -- LOAD R0, 12
          result = matchWildcardPattern program pattern
      result `shouldBe` Just Map.empty

    it "AddressWildcard (invalid)" $ do
      let pattern = createWildcardPattern [FixedByte 9, AddressWildcard] [] "LOAD R0 from any address" 0.7
          program = [9, 16]  -- Invalid address > 15
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

  context "Program Generalization" $ do
    it "wildcardFromProgram" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT
          generatedPattern = wildcardFromProgram program "Generated pattern"
          -- Test that it can match the original program
          result = matchWildcardPattern program generatedPattern
      result `shouldSatisfy` (\x -> case x of Just _ -> True; Nothing -> False)

    it "Generalization Confidence" $ do
      let program = [8, 15, 0]
          generatedPattern = wildcardFromProgram program "Test confidence"
          confidence = wildcardConfidence generatedPattern
      confidence `shouldSatisfy` (\c -> c >= 0.3 && c <= 0.9)

  context "Edge Cases" $ do
    it "Empty Pattern" $ do
      let pattern = createWildcardPattern [] [] "Empty pattern" 1.0
          program = []
          result = matchWildcardPattern program pattern
      result `shouldBe` Just Map.empty

    it "Empty Program" $ do
      let pattern = createWildcardPattern [FixedByte 8] [] "Non-empty pattern" 1.0
          program = []
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

    it "Length Mismatch" $ do
      let pattern = createWildcardPattern [FixedByte 8, FixedByte 15] [] "Two bytes" 1.0
          program = [8, 15, 0]  -- Three bytes
          result = matchWildcardPattern program pattern
      result `shouldBe` Nothing

    it "Complex Pattern with Multiple Constraints" $ do
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
      result `shouldBe` Just (Map.fromList [("val1", 15), ("val2", 5), ("addr", 0)])