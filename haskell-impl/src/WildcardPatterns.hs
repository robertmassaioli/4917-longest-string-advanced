{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module WildcardPatterns
    ( PatternElement(..)
    , WildcardPattern(..)
    , Constraint(..)
    , VariableBinding
    , createWildcardPattern
    , matchWildcardPattern
    , extractVariables
    , evaluateConstraints
    , wildcardFromProgram
    , isWildcardMatch
    ) where

import Data.Map (Map)
import qualified Data.Map as Map
import Data.Word (Word8)
import Data.List (group, sort, isInfixOf)
import GHC.Generics (Generic)
import Control.DeepSeq (NFData, rnf)

-- | A single element in a wildcard pattern
data PatternElement
    = FixedByte Word8           -- Exact byte match
    | Variable String           -- Named variable (e.g., "addr", "value")
    | AnyByte                   -- Wildcard matching any single byte
    | InstructionWildcard       -- Matches any instruction (0-15)
    | AddressWildcard           -- Matches any memory address (0-15)
    deriving (Show, Eq, Ord, Generic)

instance NFData PatternElement where
    rnf (FixedByte b) = rnf b
    rnf (Variable s) = rnf s
    rnf AnyByte = ()
    rnf InstructionWildcard = ()
    rnf AddressWildcard = ()

-- | Constraints on pattern variables
data Constraint
    = Equal String Word8        -- Variable must equal specific value
    | NotEqual String Word8     -- Variable must not equal specific value
    | InRange String Word8 Word8 -- Variable must be in range [min, max]
    | SameAs String String      -- Two variables must have same value
    | DifferentFrom String String -- Two variables must have different values
    deriving (Show, Eq, Ord, Generic)

instance NFData Constraint

-- | Type alias for variable bindings during pattern matching
type VariableBinding = Map String Word8

-- | A complete wildcard pattern
data WildcardPattern = WildcardPattern
    { wildcardElements :: [PatternElement]  -- Pattern elements
    , wildcardConstraints :: [Constraint]   -- Constraints on variables
    , wildcardDescription :: String         -- Human-readable description
    , wildcardConfidence :: Double          -- Confidence in this pattern (0.0-1.0)
    } deriving (Show, Eq, Generic)

instance NFData WildcardPattern where
    rnf (WildcardPattern elems constrs desc conf) = 
        rnf elems `seq` rnf constrs `seq` rnf desc `seq` rnf conf

-- | Create a wildcard pattern from pattern elements and constraints
createWildcardPattern :: [PatternElement] -> [Constraint] -> String -> Double -> WildcardPattern
createWildcardPattern elements constraints description confidence = WildcardPattern
    { wildcardElements = elements
    , wildcardConstraints = constraints
    , wildcardDescription = description
    , wildcardConfidence = max 0.0 (min 1.0 confidence)
    }

-- | Match a program against a wildcard pattern
matchWildcardPattern :: [Word8] -> WildcardPattern -> Maybe VariableBinding
matchWildcardPattern program pattern = do
    bindings <- matchElements program (wildcardElements pattern) Map.empty
    if evaluateConstraints bindings (wildcardConstraints pattern)
        then Just bindings
        else Nothing

-- | Match program bytes against pattern elements, building variable bindings
matchElements :: [Word8] -> [PatternElement] -> VariableBinding -> Maybe VariableBinding
matchElements [] [] bindings = Just bindings
matchElements [] _ _ = Nothing  -- Pattern longer than program
matchElements _ [] _ = Nothing  -- Program longer than pattern
matchElements (byte:restBytes) (element:restElements) bindings = do
    newBindings <- matchElement byte element bindings
    matchElements restBytes restElements newBindings

-- | Match a single byte against a pattern element
matchElement :: Word8 -> PatternElement -> VariableBinding -> Maybe VariableBinding
matchElement byte element bindings = case element of
    FixedByte expected -> 
        if byte == expected 
            then Just bindings 
            else Nothing
    
    AnyByte -> Just bindings
    
    InstructionWildcard -> 
        if byte <= 15 
            then Just bindings 
            else Nothing
    
    AddressWildcard -> 
        if byte <= 15 
            then Just bindings 
            else Nothing
    
    Variable varName -> case Map.lookup varName bindings of
        Nothing -> Just (Map.insert varName byte bindings)  -- Bind new variable
        Just existingValue -> 
            if byte == existingValue 
                then Just bindings  -- Consistent with existing binding
                else Nothing        -- Inconsistent binding

-- | Extract all variable names from a wildcard pattern
extractVariables :: WildcardPattern -> [String]
extractVariables pattern = 
    let elementVars = concatMap getElementVars (wildcardElements pattern)
        constraintVars = concatMap getConstraintVars (wildcardConstraints pattern)
    in map head . group . sort $ elementVars ++ constraintVars
  where
    getElementVars (Variable name) = [name]
    getElementVars _ = []
    
    getConstraintVars (Equal name _) = [name]
    getConstraintVars (NotEqual name _) = [name]
    getConstraintVars (InRange name _ _) = [name]
    getConstraintVars (SameAs name1 name2) = [name1, name2]
    getConstraintVars (DifferentFrom name1 name2) = [name1, name2]

-- | Evaluate all constraints against variable bindings
evaluateConstraints :: VariableBinding -> [Constraint] -> Bool
evaluateConstraints bindings = all (evaluateConstraint bindings)

-- | Evaluate a single constraint
evaluateConstraint :: VariableBinding -> Constraint -> Bool
evaluateConstraint bindings constraint = case constraint of
    Equal varName value -> 
        case Map.lookup varName bindings of
            Just boundValue -> boundValue == value
            Nothing -> False  -- Unbound variable
    
    NotEqual varName value ->
        case Map.lookup varName bindings of
            Just boundValue -> boundValue /= value
            Nothing -> True   -- Unbound variable satisfies "not equal"
    
    InRange varName minVal maxVal ->
        case Map.lookup varName bindings of
            Just boundValue -> boundValue >= minVal && boundValue <= maxVal
            Nothing -> False
    
    SameAs varName1 varName2 ->
        case (Map.lookup varName1 bindings, Map.lookup varName2 bindings) of
            (Just val1, Just val2) -> val1 == val2
            _ -> False
    
    DifferentFrom varName1 varName2 ->
        case (Map.lookup varName1 bindings, Map.lookup varName2 bindings) of
            (Just val1, Just val2) -> val1 /= val2
            _ -> True  -- If either unbound, they're different

-- | Convert a concrete program to a wildcard pattern by introducing variables
wildcardFromProgram :: [Word8] -> String -> WildcardPattern
wildcardFromProgram program description = 
    let elements = analyzeAndGeneralize program
        constraints = generateConstraints elements
        confidence = calculateGeneralizationConfidence elements
    in createWildcardPattern elements constraints description confidence

-- | Analyze a program and create generalized pattern elements
analyzeAndGeneralize :: [Word8] -> [PatternElement]
analyzeAndGeneralize program = analyzeInstructionSequence 0 program
  where
    analyzeInstructionSequence :: Int -> [Word8] -> [PatternElement]
    analyzeInstructionSequence _ [] = []
    analyzeInstructionSequence addr (inst:rest)
        | hasOperand inst = case rest of
            [] -> [FixedByte inst]  -- Instruction without operand
            (operand:remaining) -> 
                let instElement = if shouldGeneralizeInstruction inst 
                                   then InstructionWildcard 
                                   else FixedByte inst
                    operandElement = if shouldGeneralizeOperand inst operand
                                      then Variable ("operand_" ++ show addr)
                                      else FixedByte operand
                in instElement : operandElement : analyzeInstructionSequence (addr + 2) remaining
        | otherwise = 
            let element = if shouldGeneralizeInstruction inst
                           then InstructionWildcard
                           else FixedByte inst
            in element : analyzeInstructionSequence (addr + 1) rest

-- | Check if an instruction has an operand (instructions 8-15)
hasOperand :: Word8 -> Bool
hasOperand inst = inst >= 8 && inst <= 15

-- | Decide whether to generalize an instruction
shouldGeneralizeInstruction :: Word8 -> Bool
shouldGeneralizeInstruction inst = case inst of
    8  -> False  -- OUTPUT - keep specific for now
    13 -> True   -- JMP - addresses often vary
    14 -> True   -- JZ - addresses often vary  
    15 -> True   -- JNZ - addresses often vary
    _  -> False  -- Keep other instructions specific

-- | Decide whether to generalize an operand
shouldGeneralizeOperand :: Word8 -> Word8 -> Bool
shouldGeneralizeOperand inst operand = case inst of
    8  -> operand > 9    -- Generalize two-digit numbers in OUTPUT
    9  -> True           -- LOAD R0 - addresses often vary
    10 -> True           -- LOAD R1 - addresses often vary
    11 -> True           -- STORE R0 - addresses often vary
    12 -> True           -- STORE R1 - addresses often vary
    13 -> True           -- JMP - addresses always vary
    14 -> True           -- JZ - addresses always vary
    15 -> True           -- JNZ - addresses always vary
    _  -> False

-- | Generate constraints based on pattern elements
generateConstraints :: [PatternElement] -> [Constraint]
generateConstraints elements = 
    let variables = [name | Variable name <- elements]
        addressVars = [name | name <- variables, "addr" `isInfixOf` name || "operand" `isInfixOf` name]
    in map (\var -> InRange var 0 15) addressVars  -- All addresses must be 0-15

-- | Calculate confidence for a generalized pattern
calculateGeneralizationConfidence :: [PatternElement] -> Double
calculateGeneralizationConfidence elements = 
    let totalElements = length elements
        wildcardCount = length [e | e <- elements, isWildcardElement e]
        wildcardRatio = if totalElements > 0 
                          then fromIntegral wildcardCount / fromIntegral totalElements 
                          else 0.0
        -- Higher wildcard ratio = lower confidence but more general
        baseConfidence = 0.8 - (wildcardRatio * 0.3)
    in max 0.3 (min 0.9 baseConfidence)

-- | Check if an element is a wildcard
isWildcardElement :: PatternElement -> Bool
isWildcardElement (Variable _) = True
isWildcardElement AnyByte = True
isWildcardElement InstructionWildcard = True
isWildcardElement AddressWildcard = True
isWildcardElement (FixedByte _) = False

-- | Check if a program matches a wildcard pattern (convenience function)
isWildcardMatch :: [Word8] -> WildcardPattern -> Bool
isWildcardMatch program pattern = case matchWildcardPattern program pattern of
    Just _ -> True
    Nothing -> False

