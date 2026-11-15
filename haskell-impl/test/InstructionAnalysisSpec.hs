module InstructionAnalysisSpec (spec) where

import Data.List (nub)
import InstructionAnalysis
import ProcessorTestSupport (genProgram, shrinkProgram)
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

spec :: Spec
spec = describe "InstructionAnalysis properties and boundaries" $ do
    modifyMaxSuccess (max 300) $
        prop "parses only instruction addresses in the supplied program" $
            forAllShrink genProgram shrinkProgram $ \program ->
                let parsed = parseInstructions (map fromIntegral program)
                    addresses = map instrAddress parsed
                in all (\address -> address >= 0 && address < length program) addresses
                   && addresses == nub addresses
                   && and [instrOpcode instruction == fromIntegral (program !! instrAddress instruction)
                          | instruction <- parsed]
                   && and [maybe (not (hasOperand (instrOpcode instruction))) (const (hasOperand (instrOpcode instruction))) (instrOperand instruction)
                          | instruction <- parsed]

    it "wraps a two-byte instruction operand from address 15 to address zero" $
        parseInstructions (replicate 15 7 ++ [8])
            `shouldSatisfy` (\instructions -> case reverse instructions of
                finalInstruction:_ -> instrAddress finalInstruction == 15
                    && instrOpcode finalInstruction == 8
                    && instrOperand finalInstruction == Just 7
                [] -> False)

    it "pads an operand missing at the end of a short program with zero" $
        parseInstructions [8] `shouldSatisfy` (\instructions -> case instructions of
            [instruction] -> instrAddress instruction == 0 && instrOperand instruction == Just 0
            _ -> False)
