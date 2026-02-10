module InstructionAnalysis
    ( analyzeProgram
    , analyzeProgramToString
    , hasOperand
    , instructionDescription
    , instructionDescriptionWithOperand
    , InstructionInfo(..)
    , parseInstructions
    ) where

import Data.Word (Word8)

-- | Information about a parsed instruction
data InstructionInfo = InstructionInfo
    { instrAddress :: Int
    , instrOpcode :: Int
    , instrOperand :: Maybe Int
    , instrDescription :: String
    } deriving (Show, Eq)

-- | Analyze a program and print what it does
analyzeProgram :: [Word8] -> IO ()
analyzeProgram program = do
    putStrLn "Instruction breakdown:"
    let instructions = parseInstructions (map fromIntegral program)
    mapM_ printInstruction instructions
  where
    printInstruction info = case instrOperand info of
        Nothing -> putStrLn $ "  " ++ show (instrAddress info) ++ ": " ++ 
                             show (instrOpcode info) ++ " - " ++ instrDescription info
        Just operand -> putStrLn $ "  " ++ show (instrAddress info) ++ ": " ++ 
                                  show (instrOpcode info) ++ " " ++ show operand ++ " - " ++ instrDescription info

-- | Analyze a program and return the breakdown as a string
analyzeProgramToString :: [Word8] -> String
analyzeProgramToString program = 
    let instructions = parseInstructions (map fromIntegral program)
        lines' = map formatInstruction instructions
    in unlines ("Instruction breakdown:" : lines')
  where
    formatInstruction info = case instrOperand info of
        Nothing -> "  " ++ show (instrAddress info) ++ ": " ++ 
                   show (instrOpcode info) ++ " - " ++ instrDescription info
        Just operand -> "  " ++ show (instrAddress info) ++ ": " ++ 
                        show (instrOpcode info) ++ " " ++ show operand ++ " - " ++ instrDescription info

-- | Parse a list of bytes into instruction information
parseInstructions :: [Int] -> [InstructionInfo]
parseInstructions program = 
    let paddedProgram = take 16 (program ++ repeat 0)  -- Pad to 16 bytes with zeros
    in parseInstructionsAt 0 paddedProgram
  where
    parseInstructionsAt :: Int -> [Int] -> [InstructionInfo]
    parseInstructionsAt addr memory
        | addr >= length program = []  -- Stop parsing at end of actual program
        | otherwise = 
            let inst = memory !! addr
            in if hasOperand inst
               then if addr + 1 < 16  -- Check if operand address is within memory bounds
                    then let operand = memory !! (addr + 1)
                             info = InstructionInfo addr inst (Just operand) (instructionDescriptionWithOperand inst operand)
                         in info : parseInstructionsAt (addr + 2) memory
                    else let operand = memory !! ((addr + 1) `mod` 16)  -- Only wrap at actual memory boundary
                             info = InstructionInfo addr inst (Just operand) (instructionDescriptionWithOperand inst operand)
                         in [info]  -- Stop after wrapping instruction
               else let info = InstructionInfo addr inst Nothing (instructionDescription inst)
                    in info : parseInstructionsAt (addr + 1) memory

-- | Check if an instruction has an operand
hasOperand :: Int -> Bool
hasOperand 8  = True  -- OUTPUT
hasOperand 9  = True  -- LOAD R0
hasOperand 10 = True  -- LOAD R1
hasOperand 11 = True  -- STORE R0
hasOperand 12 = True  -- STORE R1
hasOperand 13 = True  -- JMP
hasOperand 14 = True  -- JZ
hasOperand 15 = True  -- JNZ
hasOperand _  = False

-- | Get description for an instruction
instructionDescription :: Int -> String
instructionDescription 0  = "HALT"
instructionDescription 1  = "R0 = R0 + R1"
instructionDescription 2  = "R0 = R0 - R1"
instructionDescription 3  = "R0++"
instructionDescription 4  = "R1++"
instructionDescription 5  = "R0--"
instructionDescription 6  = "R1--"
instructionDescription 7  = "Ring Bell (NOP)"
instructionDescription 8  = "PRINT (needs operand)"
instructionDescription 9  = "LOAD R0 (needs address)"
instructionDescription 10 = "LOAD R1 (needs address)"
instructionDescription 11 = "STORE R0 (needs address)"
instructionDescription 12 = "STORE R1 (needs address)"
instructionDescription 13 = "JUMP (needs address)"
instructionDescription 14 = "JUMP IF R0==0 (needs address)"
instructionDescription 15 = "JUMP IF R0!=0 (needs address)"
instructionDescription n   = "Unknown instruction (" ++ show n ++ ")"

-- | Get description for an instruction with its operand
instructionDescriptionWithOperand :: Int -> Int -> String
instructionDescriptionWithOperand 8 operand  = "PRINT " ++ show operand
instructionDescriptionWithOperand 9 operand  = "LOAD R0 from address " ++ show operand
instructionDescriptionWithOperand 10 operand = "LOAD R1 from address " ++ show operand
instructionDescriptionWithOperand 11 operand = "STORE R0 to address " ++ show operand
instructionDescriptionWithOperand 12 operand = "STORE R1 to address " ++ show operand
instructionDescriptionWithOperand 13 operand = "JUMP to address " ++ show operand
instructionDescriptionWithOperand 14 operand = "JUMP to address " ++ show operand ++ " if R0==0"
instructionDescriptionWithOperand 15 operand = "JUMP to address " ++ show operand ++ " if R0!=0"
instructionDescriptionWithOperand inst operand = "Unknown instruction " ++ show inst ++ " with operand " ++ show operand