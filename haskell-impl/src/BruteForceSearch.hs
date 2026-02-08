{-# LANGUAGE RecordWildCards #-}

module BruteForceSearch
    ( generateAllPrograms
    , findLongestOutputProgram
    , ProgramResult(..)
    ) where

import Processor (Device(..), Byte, createDevice, runProgramLoopCheck)
import Data.List (maximumBy)
import Data.Ord (comparing)
import Data.Vector.Unboxed ((!))  -- For vector indexing

-- | Result of testing a program
data ProgramResult = ProgramResult
    { program :: Device
    , outputLength :: Int
    , programBytes :: [Byte]
    } deriving (Show, Eq)

-- | Generate all possible programs of a given length
-- Each instruction is 4 bits (0-15), so we generate all combinations
generateAllPrograms :: Int -> [Device]
generateAllPrograms programLength = map createDevice allPrograms
  where
    -- Generate all possible instruction sequences
    allPrograms = sequence (replicate programLength [0..15])

-- | Find the program that produces the longest output string
-- Returns Nothing if no programs produce output, or if length is too large
findLongestOutputProgram :: Int -> Maybe ProgramResult
findLongestOutputProgram programLength 
    | programLength <= 0 = Nothing
    | programLength > 10 = Nothing  -- Safety limit to prevent excessive computation
    | otherwise = 
        let allPrograms = generateAllPrograms programLength
            results = map testProgram allPrograms
            validResults = filter (\r -> outputLength r > 0) results
        in if null validResults 
           then Nothing
           else Just $ maximumBy (comparing outputLength) validResults
  where
    testProgram :: Device -> ProgramResult
    testProgram device = 
        let output = runProgramLoopCheck device
            bytes = take programLength $ extractProgramBytes device
        in ProgramResult
            { program = device
            , outputLength = output
            , programBytes = bytes
            }
    
    -- Extract the program bytes from a device's memory
    extractProgramBytes :: Device -> [Byte]
    extractProgramBytes Device{..} = [memory ! i | i <- [0..15]]

-- | Pretty print a program result
showProgramResult :: ProgramResult -> String
showProgramResult ProgramResult{..} =
    "Program: " ++ show programBytes ++ 
    " -> Output length: " ++ show outputLength

-- | Find and display the best program for each length up to maxLength
findBestPrograms :: Int -> IO ()
findBestPrograms maxLength = do
    putStrLn $ "Finding best programs for lengths 1 to " ++ show maxLength ++ "..."
    mapM_ findAndShowBest [1..maxLength]
  where
    findAndShowBest len = do
        putStr $ "Length " ++ show len ++ ": "
        case findLongestOutputProgram len of
            Nothing -> putStrLn "No programs found that produce output"
            Just result -> putStrLn $ showProgramResult result