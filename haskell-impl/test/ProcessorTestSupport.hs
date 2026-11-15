module ProcessorTestSupport
    ( RefState(..)
    , genDevice
    , genInstructionDevice
    , genNibble
    , genProgram
    , shrinkProgram
    , genTerminatingProgram
    , shrinkTerminatingProgram
    , fromDevice
    , toDevice
    , referenceStep
    , referenceRun
    , shrinkDevice
    ) where

import Data.Bits ((.&.))
import Data.Word (Word8)
import qualified Data.Vector.Unboxed as V
import Processor
import Test.QuickCheck (Gen, chooseInt, vectorOf, shrink)

-- A plain-list reference model, intentionally separate from Processor.Device
-- and the production vector-based implementation.
data RefState = RefState
    { refMemory :: [Word8]
    , refR0 :: Word8
    , refR1 :: Word8
    , refPc :: Word8
    , refOutputCount :: Int
    } deriving (Show, Eq)

genNibble :: Gen Word8
genNibble = fromIntegral <$> chooseInt (0, 15)

genProgram :: Gen [Word8]
genProgram = do
    size <- chooseInt (1, 16)
    vectorOf size genNibble

shrinkProgram :: [Word8] -> [[Word8]]
shrinkProgram program =
    [take size program | size <- shrink (length program), size > 0]
    ++ [take index program ++ [smaller] ++ drop (index + 1) program
       | (index, value) <- zip [0..] program
       , smaller <- shrink value
       , smaller <= 15]

genTerminatingProgram :: Gen [Word8]
genTerminatingProgram = do
    size <- chooseInt (0, 15)
    prefix <- vectorOf size (fromIntegral <$> chooseInt (1, 7))
    pure (prefix ++ [0])

shrinkTerminatingProgram :: [Word8] -> [[Word8]]
shrinkTerminatingProgram program =
    let prefix = if null program then [] else init program
    in [take size prefix ++ [0] | size <- shrink (length prefix), size >= 0]
       ++ [take index prefix ++ [smaller] ++ drop (index + 1) prefix ++ [0]
          | (index, value) <- zip [0..] prefix
          , smaller <- shrink value
          , smaller >= 1
          , smaller <= 7]

genDevice :: Gen Device
genDevice = do
    cells <- vectorOf 16 genNibble
    register0 <- genNibble
    register1 <- genNibble
    counter <- fromIntegral <$> chooseInt (0, 15)
    output <- chooseInt (0, 200)
    pure (Device (V.fromList cells) register0 register1 counter output)

genInstructionDevice :: Gen (Device, Word8)
genInstructionDevice = do
    device <- genDevice
    address <- chooseInt (0, 15)
    opcode <- genNibble
    operand <- genNibble
    let cells = V.toList (memory device)
        cellsWithOpcode = replace address opcode cells
        cellsWithOperand = if opcode >= 8
            then replace ((address + 1) `mod` 16) operand cellsWithOpcode
            else cellsWithOpcode
        selected = device
            { memory = V.fromList cellsWithOperand
            , pc = fromIntegral address
            }
    pure (selected, opcode)
  where
    replace index value values = take index values ++ [value] ++ drop (index + 1) values

fromDevice :: Device -> RefState
fromDevice device = RefState
    { refMemory = V.toList (memory device)
    , refR0 = r0 device
    , refR1 = r1 device
    , refPc = pc device
    , refOutputCount = outputCount device
    }

toDevice :: RefState -> Device
toDevice state = Device
    { memory = V.fromList (refMemory state)
    , r0 = refR0 state
    , r1 = refR1 state
    , pc = refPc state
    , outputCount = refOutputCount state
    }

referenceStep :: RefState -> (RefState, OutputInfo, Bool)
referenceStep state = (after, outputInfo, finished)
  where
    cells = refMemory state
    address = fromIntegral (refPc state)
    opcode = at address cells
    operandAddress = (address + 1) `mod` 16
    operand = at operandAddress cells
    nextAddress = fromIntegral ((address + 1) `mod` 16)
    nextAfterOperand = fromIntegral ((address + 2) `mod` 16)
    valueAtOperand = at (fromIntegral operand) cells
    r0' = fromIntegral (refR0 state) :: Int
    r1' = fromIntegral (refR1 state) :: Int
    (newCells, newR0, newR1, newPc, outputInfo, finished) = case opcode of
        0 -> (cells, refR0 state, refR1 state, nextAddress, NoOutput, True)
        1 -> (cells, nibble (r0' + r1'), refR1 state, nextAddress, NoOutput, False)
        2 -> (cells, nibble (r0' - r1'), refR1 state, nextAddress, NoOutput, False)
        3 -> (cells, nibble (r0' + 1), refR1 state, nextAddress, NoOutput, False)
        4 -> (cells, refR0 state, nibble (r1' + 1), nextAddress, NoOutput, False)
        5 -> (cells, nibble (r0' - 1), refR1 state, nextAddress, NoOutput, False)
        6 -> (cells, refR0 state, nibble (r1' - 1), nextAddress, NoOutput, False)
        7 -> (cells, refR0 state, refR1 state, nextAddress, NoOutput, False)
        8 -> (cells, refR0 state, refR1 state, nextAfterOperand,
              if operand < 10 then OneDigit else TwoDigits, False)
        9 -> (cells, valueAtOperand, refR1 state, nextAfterOperand, NoOutput, False)
        10 -> (cells, refR0 state, valueAtOperand, nextAfterOperand, NoOutput, False)
        11 -> (writeAt (fromIntegral operand) (refR0 state) cells,
               refR0 state, refR1 state, nextAfterOperand, NoOutput, False)
        12 -> (writeAt (fromIntegral operand) (refR1 state) cells,
               refR0 state, refR1 state, nextAfterOperand, NoOutput, False)
        13 -> (cells, refR0 state, refR1 state, operand, NoOutput, False)
        14 -> (cells, refR0 state, refR1 state,
               if refR0 state == 0 then operand else nextAfterOperand, NoOutput, False)
        15 -> (cells, refR0 state, refR1 state,
               if refR0 state /= 0 then operand else nextAfterOperand, NoOutput, False)
        _ -> (cells, refR0 state, refR1 state, nextAddress, NoOutput, False)
    outputDelta = outputInfoToCount outputInfo
    after = RefState newCells newR0 newR1 newPc (refOutputCount state + outputDelta)

    at index xs = xs !! index
    writeAt index value xs = take index xs ++ [value] ++ drop (index + 1) xs
    nibble n = fromIntegral (n .&. 15)

referenceRun :: RefState -> Int -> (RefState, Bool, Int)
referenceRun initial limit = go initial (max 0 limit) 0
  where
    go state 0 count = (state, False, count)
    go state remaining count =
        let (next, output, finished) = referenceStep state
            newCount = count + outputInfoToCount output
        in if finished
           then (next, True, newCount)
           else go next (remaining - 1) newCount

shrinkDevice :: Device -> [Device]
shrinkDevice device =
    [ device { r0 = 0 } | r0 device /= 0 ]
    ++ [ device { r1 = 0 } | r1 device /= 0 ]
    ++ [ device { pc = 0 } | pc device /= 0 ]
    ++ [ device { outputCount = 0 } | outputCount device /= 0 ]
    ++ [ device { memory = memory device V.// [(index, 0)] }
       | (index, value) <- zip [0..] (V.toList (memory device))
       , value /= 0]
