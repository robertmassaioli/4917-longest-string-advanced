module ProgramExecutionSpec (spec) where

import Commands.ProgramExecution
import Processor (Byte)
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck
import Data.List (isInfixOf, isPrefixOf)
import ProcessorTestSupport (genProgram, shrinkProgram)

spec :: Spec
spec = do
    describe "parseProgramBytes" $ do
        it "parses valid bytes including values 10 through 15" $
            parseProgramBytes "8,10,11,12,13,14,15,0" `shouldBe` Right ([8,10,11,12,13,14,15,0] :: [Byte])
        it "rejects empty input, malformed values, out-of-range values, and excess bytes" $ do
            parseProgramBytes "" `shouldSatisfy` isLeft
            parseProgramBytes "1,,2" `shouldSatisfy` isLeft
            parseProgramBytes "16" `shouldSatisfy` isLeft
            parseProgramBytes "+1" `shouldSatisfy` isLeft
            parseProgramBytes " 1" `shouldSatisfy` isLeft
            parseProgramBytes "1 " `shouldSatisfy` isLeft
            parseProgramBytes "1, 2" `shouldSatisfy` isLeft
            parseProgramBytes "1,-2" `shouldSatisfy` isLeft
            parseProgramBytes "1,x" `shouldSatisfy` isLeft
            parseProgramBytes "999999999999999999999999999999999999999" `shouldSatisfy` isLeft
            parseProgramBytes (intercalateComma (replicate 17 "1")) `shouldSatisfy` isLeft
        it "accepts the minimum and maximum valid program lengths" $ do
            parseProgramBytes "0" `shouldBe` Right [0]
            parseProgramBytes (intercalateComma (replicate 16 "15")) `shouldBe` Right (replicate 16 15)
        modifyMaxSuccess (max 300) $
            prop "round-trips generated valid machine-code programs" $
                forAllShrink genProgram shrinkProgram $ \program ->
                    parseProgramBytes (intercalateComma (map show program)) == Right program
        modifyMaxSuccess (max 300) $
            prop "rejects generated signed integers outside the nibble range" $
                forAll (oneof [chooseInt (-1000, -1), chooseInt (16, 1000)]) $ \value ->
                    isLeft (parseProgramBytes (show value))
    describe "executeProgram" $ do
        it "returns printed values in order and stops at HALT" $
            executeProgram [8,10,8,3,0] 20 `shouldBe` Halted [10,3] 3
        it "counts the HALT instruction against the limit" $
            executeProgram [0] 1 `shouldBe` Halted [] 1
        it "reports step limit exhaustion distinctly" $
            executeProgram [7,7,0] 1 `shouldBe` StepLimitReached [] 1
        it "treats negative limits as zero steps" $
            executeProgram [0] (-1) `shouldBe` StepLimitReached [] 0
        it "detects a loop even when it prints each cycle" $
            executeProgram [8,1,13,0] 20 `shouldBe` LoopDetected [1] 2
    describe "renderRunResult" $ do
        it "formats output values in order and reports decimal character length" $
            renderRunResult (Halted [15,3] 3)
                `shouldBe` "Printed values: 15,3\nHalted after 3 steps; output characters: 3"
        it "keeps loop and step-limit termination messages distinct" $ do
            renderRunResult (LoopDetected [1] 2) `shouldSatisfy` isInfixOf "Loop detected after 2 steps"
            renderRunResult (StepLimitReached [] 0) `shouldSatisfy` isInfixOf "Maximum step limit reached after 0 steps"
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
        it "prints the complete changed memory state after a self-modifying store" $ do
            let linesOut = renderTrace [3,11,2,0] 10
            linesOut !! 2 `shouldSatisfy` isInfixOf "memory: [3,11,1,0,0,0,0,0,0,0,0,0,0,0,0,0]"
            linesOut !! 3 `shouldSatisfy` isInfixOf "memory: unchanged"
        it "shows jump operands and the resulting program counter" $ do
            let linesOut = renderTrace [13,2,0] 5
            linesOut !! 1 `shouldSatisfy` isInfixOf "instruction=13 operand=2"
            linesOut !! 1 `shouldSatisfy` isInfixOf "PC=0->2"
        it "does not execute at a zero limit" $ do
            let linesOut = renderTrace [3,0] 0
            length linesOut `shouldBe` 2
            last linesOut `shouldSatisfy` isInfixOf "maximum step limit"
        modifyMaxSuccess (max 300) $
            prop "traces every instruction in generated straight-line programs through HALT" $
                forAllShrink genStraightLineProgram shrinkStraightLineProgram $ \program ->
                    let linesOut = renderTrace program 17
                        stepRows = filter (isPrefixOf "step ") linesOut
                        expectedMemory = "memory: [" ++ intercalateComma (map show (take 16 (program ++ repeat 0))) ++ "]"
                    in length stepRows == length program
                       && expectedMemory `isInfixOf` head linesOut
                       && last linesOut == "halted after " ++ show (length program) ++ " steps"
        modifyMaxSuccess (max 300) $
            prop "reports per-output and cumulative decimal character counts" $
                forAllShrink genOutputProgram shrinkOutputProgram $ \(values, program) ->
                    let rows = filter (\row -> isInfixOf "output=" row && not (isInfixOf "output=none" row)) (renderTrace program 17)
                        expectedCounts = scanl (+) 0 (map decimalCharacters values)
                    in counterexample (show (rows, values, tail expectedCounts)) $
                       length rows == length values
                       && and (zipWith3 rowMatches rows values (tail expectedCounts))
  where
    isLeft (Left _) = True
    isLeft _ = False
    intercalateComma = foldr1 (\a b -> a ++ "," ++ b)
    genStraightLineProgram = do
        size <- chooseInt (0, 15)
        prefix <- vectorOf size (chooseInt (1, 7))
        pure (map fromIntegral (prefix ++ [0]))
    shrinkStraightLineProgram program =
        let prefix = init program
        in [take smaller prefix ++ [0] | smaller <- shrink (length prefix), smaller >= 0]
           ++ [take index prefix ++ [smaller] ++ drop (index + 1) prefix ++ [0]
              | (index, value) <- zip [0..] prefix
              , smaller <- shrink value
              , smaller >= 1
              , smaller <= 7]
    genOutputProgram = do
        size <- chooseInt (0, 7)
        values <- vectorOf size (chooseInt (0, 15))
        let program = concatMap (\value -> [8, fromIntegral value]) values ++ [0]
        pure (values, program)
    shrinkOutputProgram (values, _) =
        [ (map fromIntegral smaller, concatMap (\value -> [8, fromIntegral value]) smaller ++ [0])
        | smaller <- shrinkProgram (map fromIntegral values)
        ]
        ++ [([], [0]) | not (null values)]
    decimalCharacters value = if value < 10 then 1 else 2
    rowMatches row value cumulative =
        ("output=" ++ show value) `isInfixOf` row
            && ("output-characters=" ++ show (decimalCharacters value)) `isInfixOf` row
            && ("cumulative-characters=" ++ show cumulative) `isInfixOf` row
