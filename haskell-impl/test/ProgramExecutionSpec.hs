module ProgramExecutionSpec (spec) where

import Commands.ProgramExecution
import Processor (Byte)
import Test.Hspec
import Data.List (isInfixOf, isPrefixOf)

spec :: Spec
spec = do
    describe "parseProgramBytes" $ do
        it "parses valid bytes including values 10 through 15" $
            parseProgramBytes "8,10,11,12,13,14,15,0" `shouldBe` Right ([8,10,11,12,13,14,15,0] :: [Byte])
        it "rejects empty input, malformed values, out-of-range values, and excess bytes" $ do
            parseProgramBytes "" `shouldSatisfy` isLeft
            parseProgramBytes "1,,2" `shouldSatisfy` isLeft
            parseProgramBytes "16" `shouldSatisfy` isLeft
            parseProgramBytes (intercalateComma (replicate 17 "1")) `shouldSatisfy` isLeft
    describe "executeProgram" $ do
        it "returns printed values in order and stops at HALT" $
            executeProgram [8,10,8,3,0] 20 `shouldBe` Halted [10,3] 3
        it "counts the HALT instruction against the limit" $
            executeProgram [0] 1 `shouldBe` Halted [] 1
        it "reports step limit exhaustion distinctly" $
            executeProgram [7,7,0] 1 `shouldBe` StepLimitReached [] 1
        it "detects a loop even when it prints each cycle" $
            executeProgram [8,1,13,0] 20 `shouldBe` LoopDetected [1] 2
    describe "renderTrace" $ do
        it "prints the initial full memory, instruction details, and unchanged memory" $ do
            let linesOut = renderTrace [3,0] 5
            length (filter (isPrefixOf "step ") linesOut) `shouldBe` 2
            head linesOut `shouldSatisfy` isInfixOf "memory: [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]"
            linesOut !! 1 `shouldSatisfy` isInfixOf "instruction=3"
            linesOut !! 1 `shouldSatisfy` isInfixOf "R0=0->1"
            linesOut !! 1 `shouldSatisfy` isInfixOf "memory: unchanged"
            linesOut !! 2 `shouldSatisfy` isInfixOf "HALT"
        it "shows changed memory and cumulative decimal character counts" $ do
            let linesOut = renderTrace [8,15,3,11,4,0] 10
            linesOut !! 1 `shouldSatisfy` isInfixOf "output=15"
            linesOut !! 1 `shouldSatisfy` isInfixOf "output-characters=2"
            linesOut !! 1 `shouldSatisfy` isInfixOf "cumulative-characters=2"
            linesOut !! 3 `shouldSatisfy` isInfixOf "memory: [8,15,3,11,1,0,0,0,0,0,0,0,0,0,0,0]"
        it "shows jump operands and the resulting program counter" $ do
            let linesOut = renderTrace [13,2,0] 5
            linesOut !! 1 `shouldSatisfy` isInfixOf "instruction=13 operand=2"
            linesOut !! 1 `shouldSatisfy` isInfixOf "PC=0->2"
        it "does not execute at a zero limit" $ do
            let linesOut = renderTrace [3,0] 0
            length linesOut `shouldBe` 2
            last linesOut `shouldSatisfy` isInfixOf "maximum step limit"
  where
    isLeft (Left _) = True
    isLeft _ = False
    intercalateComma = foldr1 (\a b -> a ++ "," ++ b)
