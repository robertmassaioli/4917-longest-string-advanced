module ProcessorPropertySpec (spec) where

import Data.Word (Word8)
import Control.Monad (forM_)
import qualified Data.Vector.Unboxed as V
import Processor
import ProcessorTestSupport
    ( genDevice, genInstructionDevice, shrinkDevice
    , fromDevice, toDevice, referenceStep, referenceRun
    , genTerminatingProgram, shrinkTerminatingProgram )
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

spec :: Spec
spec = describe "Processor properties and boundary regressions" $ do
    modifyMaxSuccess (max 300) $ do
        prop "matches an independent reference step for generated machine states" $
            forAllShrink genDevice shrinkDevice $ \device ->
                let (expected, expectedOutput, expectedHalted) = referenceStep (fromDevice device)
                    (actual, actualOutput, actualHalted) = stepProgram device
                in counterexample ("initial state: " ++ show device) $
                    (actual == toDevice expected
                     && actualOutput == expectedOutput
                     && actualHalted == expectedHalted)

        prop "matches the reference step for every opcode at every PC, including wrapped operands" $
            forAllShrink genInstructionDevice (\(device, opcode) ->
                [(smaller, opcode) | smaller <- shrinkDevice device]) $ \(device, _) ->
                let (expected, expectedOutput, expectedHalted) = referenceStep (fromDevice device)
                    (actual, actualOutput, actualHalted) = stepProgram device
                in counterexample ("initial state: " ++ show device) $
                    (actual == toDevice expected
                     && actualOutput == expectedOutput
                     && actualHalted == expectedHalted)

        prop "keeps PC and memory within the fixed machine dimensions" $
            forAll genDevice $ \device ->
                let (next, _, _) = stepProgram device
                in pc next < 16 && V.length (memory next) == 16

        prop "bounded execution agrees with repeated reference stepping whenever the program halts" $
            forAll ((,) <$> genDevice <*> chooseInt (1, 40)) $ \(device, limit) ->
                let initialized = initProgram device
                    (_, finished, output) = referenceRun (fromDevice initialized) limit
                    expected = if finished then ProgramCompleted output else ProgramTimedOut output
                in runProgramResult device limit == expected

        prop "matches the reference result for every bound on generated terminating programs" $
            forAllShrink genTerminatingProgram shrinkTerminatingProgram $ \program ->
                let device = createDevice program
                    initialized = initProgram device
                    checkLimit limit =
                        let (_, finished, output) = referenceRun (fromDevice initialized) limit
                            expected = if finished then ProgramCompleted output else ProgramTimedOut output
                        in runProgramResult device limit == expected
                in all checkLimit [0..length program + 2]

    describe "arithmetic and program-counter boundaries" $ do
        it "checks every opcode at every PC with low/high operands and register values" $
            forM_ [0..15] $ \opcode ->
                forM_ [0..15] $ \address ->
                    forM_ [0,9,10,15] $ \operand ->
                        forM_ [0,15] $ \register0 ->
                            forM_ [0,15] $ \register1 -> do
                                let cellsWithOpcode = replaceAt address (fromIntegral opcode) (replicate 16 0)
                                    operandAddress = (address + 1) `mod` 16
                                    cells = if opcode >= 8
                                        then replaceAt operandAddress (fromIntegral operand) cellsWithOpcode
                                        else cellsWithOpcode
                                    device = (createDevice cells)
                                        { pc = fromIntegral address
                                        , r0 = fromIntegral register0
                                        , r1 = fromIntegral register1
                                        }
                                    (expected, expectedOutput, expectedHalted) = referenceStep (fromDevice device)
                                    (actual, actualOutput, actualHalted) = stepProgram device
                                if actual == toDevice expected
                                   && actualOutput == expectedOutput
                                   && actualHalted == expectedHalted
                                then pure ()
                                else expectationFailure ("reference mismatch: opcode=" ++ show opcode
                                    ++ ", address=" ++ show address ++ ", operand=" ++ show operand
                                    ++ ", actual=" ++ show (actual, actualOutput, actualHalted)
                                    ++ ", expected=" ++ show (toDevice expected, expectedOutput, expectedHalted))

        it "loads from and stores to every memory address" $
            forM_ [9..12] $ \opcode ->
                forM_ [0..15] $ \target ->
                    forM_ [0,15] $ \registerValue -> do
                        let base = replaceAt 1 (fromIntegral target)
                                (replaceAt 0 (fromIntegral opcode) (replicate 16 0))
                            initializedMemory = if target > 1
                                then replaceAt target 12 base
                                else base
                            device = (createDevice initializedMemory)
                                { r0 = fromIntegral registerValue
                                , r1 = fromIntegral registerValue
                                }
                            (expected, expectedOutput, expectedHalted) = referenceStep (fromDevice device)
                            (actual, actualOutput, actualHalted) = stepProgram device
                        if actual == toDevice expected
                           && actualOutput == expectedOutput
                           && actualHalted == expectedHalted
                        then pure ()
                        else expectationFailure ("memory address=" ++ show target ++ ", opcode=" ++ show opcode
                            ++ ", actual=" ++ show actual ++ ", expected=" ++ show (toDevice expected))

        it "wraps arithmetic operations over the full nibble domain" $
            [(fromIntegral a, fromIntegral b,
              arithmeticResult 1 (fromIntegral a) (fromIntegral b),
              arithmeticResult 2 (fromIntegral a) (fromIntegral b))
                | a <- [0..15 :: Int], b <- [0..15 :: Int]] `shouldBe`
            [(a,b,(a+b) `mod` 16,(a-b) `mod` 16) | a <- [0..15], b <- [0..15]]
        it "wraps one-byte instructions from PC 15 to PC 0" $ do
            let device = (createDevice (replicate 15 7 ++ [3])) { pc = 15, r0 = 15 }
                (next, output, halted) = stepProgram device
            pc next `shouldBe` 0
            r0 next `shouldBe` 0
            output `shouldBe` NoOutput
            halted `shouldBe` False
        it "fetches a two-byte operand from address zero when the opcode is at PC 15" $ do
            let device = (createDevice (15 : replicate 14 7 ++ [8])) { pc = 15 }
                (next, output, halted) = stepProgram device
            pc next `shouldBe` 1
            outputCount next `shouldBe` 2
            output `shouldBe` TwoDigits
            halted `shouldBe` False
        it "fetches a two-byte operand at cell 15 and wraps the next PC" $ do
            let cells = replicate 14 7 ++ [8, 10]
                device = (createDevice cells) { pc = 14 }
                (next, output, halted) = stepProgram device
            pc next `shouldBe` 0
            outputCount next `shouldBe` 2
            output `shouldBe` TwoDigits
            halted `shouldBe` False
        it "uses the byte at address zero as the operand for an opcode at PC 15" $
            case stepProgram ((createDevice (5 : replicate 14 7 ++ [9])) { pc = 15 }) of
                (next, _, _) -> r0 next `shouldBe` 7
        it "treats an out-of-range opcode as a NOP" $
            stepProgram (createDevice [16]) `shouldBe`
                ((createDevice [16]) { pc = 1 }, NoOutput, False)

    describe "construction and execution limits" $ do
        it "pads short memories and truncates overlong memories to 16 cells" $ do
            V.length (memory (createDevice [])) `shouldBe` 16
            V.toList (memory (createDevice [1,2])) `shouldBe` [1,2] ++ replicate 14 0
            V.toList (memory (createDevice [0..20])) `shouldBe` [0..15]
        it "reports the timeout/zero-output ambiguity in the legacy API and pins the expected compatibility result" $
            runProgram (createDevice [7,7,0]) 1 `shouldBe` 0
        it "distinguishes a zero-output timeout from a zero-output halt" $ do
            runProgramResult (createDevice [7,7,0]) 1 `shouldBe` ProgramTimedOut 0
            runProgramResult (createDevice [0]) 1 `shouldBe` ProgramCompleted 0
        it "preserves output produced before a timeout" $
            runProgramResult (createDevice [8,15,7,0]) 1 `shouldBe` ProgramTimedOut 2
        it "handles bounds on both sides of the four-step unrolled path" $
            forM_ [0..7] $ \limit ->
                runProgramResult (createDevice [8,15,8,2,8,10,0]) limit
                    `shouldBe` case limit of
                        0 -> ProgramTimedOut 0
                        1 -> ProgramTimedOut 2
                        2 -> ProgramTimedOut 3
                        3 -> ProgramTimedOut 5
                        _ -> ProgramCompleted 5
        it "halts exactly on the supplied step bound and counts HALT as a step" $
            runProgram (createDevice [8,15,0]) 3 `shouldBe` 2
        it "returns zero for a zero bound without executing a printing instruction" $
            runProgram (createDevice [8,15,0]) 0 `shouldBe` 0
        it "reports a negative bound as an immediate timeout" $
            runProgramResult (createDevice [8,15,0]) (-1) `shouldBe` ProgramTimedOut 0

    describe "loop-state equality" $ do
        it "ignores only the accumulated output count" $ do
            let original = createDevice [7]
                moreOutput = original { outputCount = 99 }
            sameExecutionState original moreOutput `shouldBe` True
            comparePrograms original moreOutput `shouldBe` False
        it "compares each register, PC, and memory cell" $ do
            let original = createDevice [7]
                changed = [ original { r0 = 1 }
                          , original { r1 = 1 }
                          , original { pc = 1 }
                          ] ++ [original { memory = memory original V.// [(address, 1)] } | address <- [0..15]]
            map (sameExecutionState original) changed `shouldBe` replicate 19 False

arithmeticResult :: Word8 -> Word8 -> Word8 -> Int
arithmeticResult opcode left right = fromIntegral result
  where
    device = (createDevice [opcode]) { r0 = left, r1 = right }
    (resultDevice, _, _) = stepProgram device
    result = r0 resultDevice

replaceAt :: Int -> a -> [a] -> [a]
replaceAt index value values = take index values ++ [value] ++ drop (index + 1) values
