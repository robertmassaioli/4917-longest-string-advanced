{-# LANGUAGE RecordWildCards #-}

module ExecutionTracing
    ( ExecutionTrace(..)
    , ProgramResult(..)
    , TerminationType(..)
    , ExecutionState(..)
    , TracePoint(..)
    , runProgramWithTracing
    , extractExecutionFingerprint
    ) where

import Processor (Device(..), Byte, createDevice, runStep, isHalted, getOutput)
import Data.Vector.Unboxed ((!))
import Control.DeepSeq (NFData, rnf)
import Data.Time (UTCTime, getCurrentTime)

-- | Types of program termination
data TerminationType 
    = Halt          -- Program executed HALT instruction (0)
    | Timeout       -- Program exceeded step limit
    | InfiniteLoop  -- Detected infinite loop
    | Error         -- Runtime error occurred
    deriving (Show, Eq, Ord)

instance NFData TerminationType where
    rnf x = x `seq` ()

-- | Snapshot of execution state at a specific point
data ExecutionState = ExecutionState
    { stateR0 :: Byte
    , stateR1 :: Byte
    , statePC :: Byte
    , stateStep :: Int
    , stateOutput :: String
    , stateLastInstruction :: Maybe Byte
    } deriving (Show, Eq)

instance NFData ExecutionState where
    rnf (ExecutionState r0 r1 pc step out inst) = 
        rnf r0 `seq` rnf r1 `seq` rnf pc `seq` rnf step `seq` rnf out `seq` rnf inst

-- | Key execution trace points
data TracePoint 
    = StepTrace Int ExecutionState     -- Periodic state capture
    | OutputTrace Int String          -- When output is generated
    | LoopDetected Int ExecutionState -- When loop is detected
    | HaltTrace Int ExecutionState    -- When HALT is executed
    deriving (Show, Eq)

instance NFData TracePoint where
    rnf (StepTrace i s) = rnf i `seq` rnf s
    rnf (OutputTrace i s) = rnf i `seq` rnf s
    rnf (LoopDetected i s) = rnf i `seq` rnf s
    rnf (HaltTrace i s) = rnf i `seq` rnf s

-- | Complete execution trace
data ExecutionTrace = ExecutionTrace
    { tracePoints :: [TracePoint]
    , totalSteps :: Int
    , finalState :: ExecutionState
    } deriving (Show, Eq)

instance NFData ExecutionTrace where
    rnf (ExecutionTrace points steps final) = 
        rnf points `seq` rnf steps `seq` rnf final

-- | Enhanced program result with execution trace
data ProgramResult = ProgramResult
    { resultOutput :: String
    , resultSteps :: Int
    , resultTermination :: TerminationType
    , resultTrace :: ExecutionTrace
    , resultProgram :: [Byte]
    , resultTimestamp :: UTCTime
    } deriving (Show, Eq)

instance NFData ProgramResult where
    rnf (ProgramResult out steps term trace prog time) = 
        rnf out `seq` rnf steps `seq` rnf term `seq` rnf trace `seq` rnf prog `seq` rnf time

-- | Run program with detailed execution tracing
runProgramWithTracing :: [Byte] -> IO ProgramResult
runProgramWithTracing program = do
    timestamp <- getCurrentTime
    let device = createDeviceFromProgram program
        (finalDevice, trace, termination) = executeWithTracing device 1000  -- 1000 step limit
        output = getOutput finalDevice
        steps = totalSteps trace
    
    return ProgramResult
        { resultOutput = output
        , resultSteps = steps
        , resultTermination = termination
        , resultTrace = trace
        , resultProgram = program
        , resultTimestamp = timestamp
        }

-- | Create device from program bytes
createDeviceFromProgram :: [Byte] -> Device
createDeviceFromProgram program = 
    let paddedProgram = take 16 (program ++ repeat 0)  -- Pad to 16 bytes
    in createDevice paddedProgram  -- Assuming this exists in Processor module

-- | Execute program with detailed state tracing
executeWithTracing :: Device -> Int -> (Device, ExecutionTrace, TerminationType)
executeWithTracing device stepLimit = 
    executeLoop device [] 0 stepLimit Nothing
  where
    executeLoop :: Device -> [TracePoint] -> Int -> Int -> Maybe ExecutionState -> (Device, ExecutionTrace, TerminationType)
    executeLoop dev traces step limit lastState
        | step >= limit = 
            let finalTrace = ExecutionTrace (reverse traces) step (captureState dev step)
            in (dev, finalTrace, Timeout)
        | isHalted dev = 
            let finalState = captureState dev step
                haltTrace = HaltTrace step finalState
                finalTrace = ExecutionTrace (reverse (haltTrace:traces)) step finalState
            in (dev, finalTrace, Halt)
        | Just lastSt <- lastState, statesEqual (captureState dev step) lastSt = 
            let finalState = captureState dev step
                loopTrace = LoopDetected step finalState
                finalTrace = ExecutionTrace (reverse (loopTrace:traces)) step finalState
            in (dev, finalTrace, InfiniteLoop)
        | otherwise = 
            let currentState = captureState dev step
                newTraces = addTracePoint step currentState traces
                (newDev, success) = safeRunStep dev
            in if success
               then executeLoop newDev newTraces (step + 1) limit (Just currentState)
               else let finalTrace = ExecutionTrace (reverse traces) step currentState
                    in (dev, finalTrace, Error)

-- | Safely run a single step, catching any errors
safeRunStep :: Device -> (Device, Bool)
safeRunStep device = 
    -- In a real implementation, this would catch exceptions
    -- For now, assume runStep always succeeds
    (runStep device, True)

-- | Capture current device state
captureState :: Device -> Int -> ExecutionState
captureState device@Device{..} step = ExecutionState
    { stateR0 = r0
    , stateR1 = r1
    , statePC = pc
    , stateStep = step
    , stateOutput = getOutput device
    , stateLastInstruction = if pc < 16 then Just (memory ! fromIntegral pc) else Nothing
    }

-- | Add trace point if significant
addTracePoint :: Int -> ExecutionState -> [TracePoint] -> [TracePoint]
addTracePoint step state traces
    | step `mod` 10 == 0 = StepTrace step state : traces  -- Trace every 10 steps
    | not (null (stateOutput state)) && (null traces || outputChanged) = 
        OutputTrace step (stateOutput state) : traces
    | otherwise = traces
  where
    outputChanged = case traces of
        (OutputTrace _ lastOutput : _) -> stateOutput state /= lastOutput
        _ -> True

-- | Check if two states are effectively equal (for loop detection)
statesEqual :: ExecutionState -> ExecutionState -> Bool
statesEqual s1 s2 = 
    stateR0 s1 == stateR0 s2 &&
    stateR1 s1 == stateR1 s2 &&
    statePC s1 == statePC s2 &&
    stateOutput s1 == stateOutput s2

-- | Extract a fingerprint for pattern matching
extractExecutionFingerprint :: ProgramResult -> String
extractExecutionFingerprint result = 
    let term = case resultTermination result of
            Halt -> "H"
            Timeout -> "T" 
            InfiniteLoop -> "L"
            Error -> "E"
        outputLen = length (resultOutput result)
        steps = resultSteps result
    in concat [term, ":", show outputLen, ":", show steps]