{-# LANGUAGE RecordWildCards #-}

module ClientResults
    ( RunResult(..)
    , ClientResults(..)
    , newClientResults
    , addResult
    , mergeResults
    , getTask
    , getLongestProgram
    , getLongestCharactersPrinted
    ) where

import Data.Word (Word32, Word64)
import qualified Data.Vector as V
import Data.Vector (Vector, (!), (//))
import Processor (Device, programLength)

-- | Result for a single program execution
data RunResult = RunResult
    { trial :: Word64           -- Packed device representation
    , charactersPrinted :: Int  -- Number of characters output
    } deriving (Show, Eq)

-- | Client results containing best results for each program length
data ClientResults = ClientResults
    { task :: Word32                    -- The task ID
    , results :: Vector RunResult       -- Results indexed by (program_length - 1)
    } deriving (Show, Eq)

-- | Create a new ClientResults for a given task
newClientResults :: Word32 -> ClientResults
newClientResults taskId = ClientResults
    { task = taskId
    , results = V.replicate 16 (RunResult 0 0)
    }

-- | Add a result if it's better than the current best for that program length
addResult :: ClientResults -> Device -> Int -> Word64 -> ClientResults
addResult clientResults@ClientResults{..} device charsPrinted packedDevice =
    let progLength = programLength device
        resultsIndex = progLength - 1
    in if progLength > 0 && resultsIndex < 16 && charsPrinted > charactersPrinted (results ! resultsIndex)
       then clientResults { results = results // [(resultsIndex, RunResult packedDevice charsPrinted)] }
       else clientResults

-- | Merge another ClientResults into this one, keeping the best results
mergeResults :: ClientResults -> ClientResults -> ClientResults
mergeResults clientResults@ClientResults{..} (ClientResults _ otherResults) =
    let mergedResults = V.imap mergeAtIndex results
        mergeAtIndex i currentResult =
            let otherResult = otherResults ! i
            in if charactersPrinted otherResult > charactersPrinted currentResult
               then otherResult
               else currentResult
    in clientResults { results = mergedResults }

-- | Get the task ID
getTask :: ClientResults -> Word32
getTask = task

-- | Get the longest program for a given program length
getLongestProgram :: ClientResults -> Int -> Word64
getLongestProgram ClientResults{..} programLength =
    if programLength > 0 && programLength <= 16
    then trial (results ! (programLength - 1))
    else 0

-- | Get the most characters printed for a given program length
getLongestCharactersPrinted :: ClientResults -> Int -> Int
getLongestCharactersPrinted ClientResults{..} programLength =
    if programLength > 0 && programLength <= 16
    then charactersPrinted (results ! (programLength - 1))
    else 0