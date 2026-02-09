{-# LANGUAGE RecordWildCards #-}

module BruteForceSearch
    ( generateAllPrograms
    , findLongestOutputProgram
    , findLongestOutputProgramTimed
    , ProgramResult(..)
    , SearchResult(..)
    , showProgramResult
    , findBestPrograms
    ) where

import Processor (Device(..), Byte, createDevice, runProgramLoopCheck)
import Data.List (maximumBy, foldl')
import Data.Ord (comparing)
import Data.Vector.Unboxed ((!))  -- For vector indexing
import System.CPUTime (getCPUTime)
import Text.Printf (printf)

-- | Result of testing a program
data ProgramResult = ProgramResult
    { program :: Device
    , outputLength :: Int
    , programBytes :: [Byte]
    } deriving (Show, Eq)

-- | Result of a timed search
data SearchResult = SearchResult
    { bestProgram :: Maybe ProgramResult
    , searchTimeMs :: Double
    , programsTested :: Int
    , programsWithOutput :: Int
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
    | programLength > 8 = Nothing  -- Extended safety limit (16^8 = 4.3 billion programs max)
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

-- | Optimized search with timing information
findLongestOutputProgramTimed :: Int -> IO SearchResult
findLongestOutputProgramTimed programLength 
    | programLength <= 0 || programLength > 8 = return $ SearchResult Nothing 0.0 0 0
    | otherwise = do
        start <- getCPUTime
        let allPrograms = generateAllPrograms programLength
            totalPrograms = length allPrograms
        
        putStrLn $ "Testing " ++ show totalPrograms ++ " programs of length " ++ show programLength ++ "..."
        
        let results = map testProgram allPrograms
            validResults = filter (\r -> outputLength r > 0) results
            validCount = length validResults
            bestResult = if null validResults 
                        then Nothing
                        else Just $ maximumBy (comparing outputLength) validResults
        
        end <- getCPUTime
        let timeDiffMs = fromIntegral (end - start) / (10^9)  -- Convert to milliseconds
        
        return $ SearchResult bestResult timeDiffMs totalPrograms validCount
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

-- | Find and display the best program for each length up to maxLength
findBestPrograms :: Int -> IO ()
findBestPrograms maxLength = do
    putStrLn $ "Finding best programs for lengths 1 to " ++ show maxLength ++ "..."
    mapM_ findAndShowBest [1..maxLength]
  where
    findAndShowBest len = do
        result <- findLongestOutputProgramTimed len
        case bestProgram result of
            Nothing -> putStrLn $ "Length " ++ show len ++ ": No programs found that produce output"
            Just prog -> do
                putStrLn $ "Length " ++ show len ++ ": " ++ showProgramResult prog
                putStrLn $ "  (" ++ show (programsWithOutput result) ++ "/" ++ 
                          show (programsTested result) ++ " programs produced output, " ++
                          printf "%.1fms" (searchTimeMs result) ++ ")"