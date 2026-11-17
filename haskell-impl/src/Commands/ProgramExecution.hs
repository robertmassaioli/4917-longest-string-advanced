{-# LANGUAGE RecordWildCards #-}

module Commands.ProgramExecution
    ( parseProgramBytes
    , RunResult(..)
    , executeProgram
    , renderRunResult
    , traceProgram
    , traceProgramUntilHaltOrCycle
    , renderTrace
    , renderTraceUntilHaltOrCycle
    , runProgramCommand
    , runTraceCommand
    ) where

import Control.Monad (when)
import Data.List (intercalate)
import qualified Data.Set as Set
import Data.Word (Word8)
import qualified Data.Vector.Unboxed as V
import Processor
import System.Exit (die)

parseProgramBytes :: String -> Either String [Byte]
parseProgramBytes input
    | null input = Left "program must contain at least one byte"
    | length fields > 16 = Left "program must contain at most 16 bytes"
    | otherwise = traverse parseByte fields
  where
    fields = splitCommas input
    parseByte field = case reads field of
        [(n, "")] | not (null field) && all isAsciiDigit field && n >= (0 :: Int) && n <= 15 -> Right (fromIntegral n :: Word8)
        _ -> Left ("invalid byte " ++ show field ++ "; expected an integer from 0 through 15")
    isAsciiDigit character = character >= '0' && character <= '9'

splitCommas :: String -> [String]
splitCommas [] = [""]
splitCommas s = case break (== ',') s of
    (field, []) -> [field]
    (field, _:rest) -> field : splitCommas rest

data RunResult = Halted [Int] Int | LoopDetected [Int] Int | StepLimitReached [Int] Int
    deriving (Show, Eq)

executeProgram :: [Byte] -> Int -> RunResult
executeProgram bytes maxSteps = go (initProgram (createDevice bytes)) 0 Set.empty []
  where
    go device steps seen values
        | steps >= max 0 maxSteps = StepLimitReached (reverse values) steps
        | Set.member (machineKey device) seen = LoopDetected (reverse values) steps
        | otherwise =
            let (next, output, halted) = stepProgram device
                emitted = if output == NoOutput then Nothing else Just (fromIntegral (memory device V.! fromIntegral ((pc device + 1) `mod` 16)))
                values' = maybe values (: values) emitted
                seen' = Set.insert (machineKey device) seen
            in if halted
               then Halted (reverse values') (steps + 1)
               else go next (steps + 1) seen' values'

machineKey :: Device -> ([Byte], Byte, Byte, Byte)
machineKey d = (V.toList (memory d), r0 d, r1 d, pc d)

data TraceRow = TraceRow
    { traceStep :: Int
    , traceAddress :: Int
    , traceInstruction :: Int
    , traceOperand :: Maybe Int
    , traceBefore :: Device
    , traceAfter :: Device
    , traceOutput :: Maybe Int
    , traceHalted :: Bool
    } deriving (Show, Eq)

data TraceResult = TraceHalted [TraceRow] Device | TraceLimit [TraceRow] Device | TraceCycle [TraceRow] Device
    deriving (Show, Eq)

traceProgram :: [Byte] -> Int -> TraceResult
traceProgram bytes maxSteps = traceProgramWithLimit (Just (max 0 maxSteps)) False bytes

traceProgramUntilHaltOrCycle :: [Byte] -> TraceResult
traceProgramUntilHaltOrCycle = traceProgramWithLimit Nothing True

traceProgramWithLimit :: Maybe Int -> Bool -> [Byte] -> TraceResult
traceProgramWithLimit maxSteps detectCycles bytes = go initial 0 [] Set.empty
  where
    initial = initProgram (createDevice bytes)
    go device steps rows seen
        | maybe False (steps >=) maxSteps = TraceLimit (reverse rows) device
        | detectCycles && Set.member (machineKey device) seen = TraceCycle (reverse rows) device
        | otherwise =
            let addr = fromIntegral (pc device)
                inst = fromIntegral (memory device V.! addr)
                operand = if inst >= 8 then Just (fromIntegral (memory device V.! ((addr + 1) `mod` 16))) else Nothing
                (next, outputInfo, halted) = stepProgram device
                emitted = if outputInfo == NoOutput then Nothing else Just (fromIntegral (memory device V.! ((addr + 1) `mod` 16)))
                row = TraceRow (steps + 1) addr inst operand device next emitted halted
                seen' = Set.insert (machineKey device) seen
            in if halted then TraceHalted (reverse (row:rows)) next else go next (steps + 1) (row:rows) seen'

renderTrace :: [Byte] -> Int -> [String]
renderTrace bytes maxSteps =
    let initial = initProgram (createDevice bytes)
    in renderTraceResult initial (traceProgram bytes maxSteps)

renderTraceUntilHaltOrCycle :: [Byte] -> [String]
renderTraceUntilHaltOrCycle bytes =
    renderTraceResult (initProgram (createDevice bytes)) (traceProgramUntilHaltOrCycle bytes)

renderTraceResult :: Device -> TraceResult -> [String]
renderTraceResult initial result =
    let (rows, status) = case result of
            TraceHalted rs _ -> (rs, "halted after " ++ show (length rs) ++ " steps")
            TraceLimit rs d -> (rs, "maximum step limit reached after " ++ show (length rs) ++ " steps; final state: " ++ renderState d)
            TraceCycle rs d -> (rs, "loop detected after " ++ show (length rs) ++ " steps; repeated state: " ++ renderState d)
        first = "initial: " ++ renderState initial ++ "; memory: " ++ renderMemory (memory initial)
        rendered = snd (foldl renderRow (memory initial, []) rows)
    in first : rendered ++ [status]
  where
    renderRow (previousMemory, linesSoFar) TraceRow{..} =
        let mem = memory traceAfter
            memText = if mem == previousMemory then "memory: unchanged" else "memory: " ++ renderMemory mem
            outputText = maybe "none" show traceOutput
            line = "step " ++ show traceStep ++ ": address=" ++ show traceAddress
                ++ " instruction=" ++ show traceInstruction
                ++ maybe "" (\op -> " operand=" ++ show op) traceOperand
                ++ " R0=" ++ show (r0 traceBefore) ++ "->" ++ show (r0 traceAfter)
                ++ " R1=" ++ show (r1 traceBefore) ++ "->" ++ show (r1 traceAfter)
                ++ " PC=" ++ show (pc traceBefore) ++ "->" ++ show (pc traceAfter)
                ++ " output=" ++ outputText
                ++ " output-characters=" ++ show (outputCount traceAfter - outputCount traceBefore)
                ++ " cumulative-characters=" ++ show (outputCount traceAfter)
                ++ " " ++ memText ++ if traceHalted then " HALT" else ""
        in (mem, linesSoFar ++ [line])

renderState :: Device -> String
renderState d = "PC=" ++ show (pc d) ++ " R0=" ++ show (r0 d) ++ " R1=" ++ show (r1 d)
    ++ " output-characters=" ++ show (outputCount d)

renderMemory :: V.Vector Word8 -> String
renderMemory mem = "[" ++ intercalate "," (map (show . (fromIntegral :: Word8 -> Int)) (V.toList mem)) ++ "]"

runProgramCommand :: String -> Int -> IO ()
runProgramCommand input maxSteps = do
    bytes <- either die pure (parseProgramBytes input)
    when (maxSteps < 0) (die "maximum step count must not be negative")
    putStrLn (renderRunResult (executeProgram bytes maxSteps))

renderRunResult :: RunResult -> String
renderRunResult result =
    let (values, steps, termination) = case result of
            Halted emitted count -> (emitted, count, "Halted")
            LoopDetected emitted count -> (emitted, count, "Loop detected")
            StepLimitReached emitted count -> (emitted, count, "Maximum step limit reached")
    in "Printed values: " ++ renderValues values ++ "\n"
       ++ termination ++ " after " ++ show steps ++ " steps; output characters: "
       ++ show (sum (map decimalChars values))
  where
    decimalChars :: Int -> Int
    renderValues = intercalate "," . map show
    decimalChars n = if n >= 10 then 2 else 1

runTraceCommand :: String -> Int -> Bool -> IO ()
runTraceCommand input maxSteps detectLoops = do
    bytes <- either die pure (parseProgramBytes input)
    when (not detectLoops && maxSteps < 0) (die "maximum step count must not be negative")
    mapM_ putStrLn (if detectLoops then renderTraceUntilHaltOrCycle bytes else renderTrace bytes maxSteps)
