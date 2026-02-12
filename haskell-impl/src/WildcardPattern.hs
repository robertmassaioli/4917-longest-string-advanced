module WildcardPattern
    ( OptimizedInstruction(..)
    , OptimizedProgram(..)
    , ProgramAnalysis(..)
    , DeadOperationAnalysis(..)
    , analyzeProgram
    , optimizeProgram
    , calculateReductionFactor
    -- Instruction category constants
    , registerManipulating
    , registerConsuming
    , nonRegisterInstructions
    , r0ManipulatingOnly
    , r1ManipulatingOnly
    , bothRegisterOperations
    , r0ConsumingOnly
    , r1ConsumingOnly
    , deadCodeEquivalentInstructions
    , r0DeadCodeEquivalent
    , r1DeadCodeEquivalent
    -- Internal functions for testing
    , identifyUnusedMemory
    , generateEquivalenceClass
    , instructionSpaceSize
    , findRegisterManipulatingPositions
    , findR0ManipulatingPositions
    , findR1ManipulatingPositions
    -- Output length categories for testing
    , singleCharOutput
    , doubleCharOutput
    -- Human-readable printing
    , prettyPrintOptimizedProgram
    , formatInstruction
    , formatByteRange
    ) where

import TrackedProcessor
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Maybe (mapMaybe)
import qualified Data.Vector.Unboxed as Vector
import Data.List (intercalate, sort)
import Text.Printf (printf)
import qualified Data.Map as Map

-- Import the usage tracking data types from TrackedProcessor
-- (No local definitions needed - use the ones from TrackedProcessor module)

-- | Core pattern types for program optimization
data OptimizedInstruction =
    Required Byte           -- Must be exactly this byte value
  | Wildcard                -- Can be any value (0-15)
  | AnyOf [Byte]           -- Can be any value from this specific list
  deriving (Show, Eq)

-- | Optimized program with wildcarding patterns
data OptimizedProgram = OptimizedProgram
    { originalProgram :: [Byte]
    , wildcardPattern :: [OptimizedInstruction]
    , reductionFactor :: Double  -- How much search space was reduced
    , equivalenceClass :: String -- Canonical representation for grouping
    , programAnalysis :: ProgramAnalysis -- NEW: Include analysis for usage information
    } deriving (Show)

-- | Memory usage classification for enhanced analysis
data MemoryUsageType =
    InstructionOnly     -- Only accessed as instruction
  | OperandOnly         -- Only accessed as operand
  | MixedUsage          -- Used as both instruction and operand
  | Unused              -- Never accessed
  deriving (Show, Eq)

-- | Enhanced memory analysis results
data EnhancedMemoryAnalysis = EnhancedMemoryAnalysis
    { memoryUsageTypes :: [MemoryUsageType]  -- Usage type for each of 16 memory positions
    , operandOutputOptimizations :: [(Int, [Byte])]  -- Position and equivalent output-length values
    } deriving (Show, Eq)

-- | Complete analysis results for a program (enhanced)
data ProgramAnalysis = ProgramAnalysis
    { programOriginal :: [Byte]
    , unusedMemoryPositions :: [Int]
    , deadRegisterPositions :: [Int]
    , registerAnalysis :: DeadOperationAnalysis
    , trackedDevice :: TrackedDevice
    , memoryAnalysis :: EnhancedMemoryAnalysis  -- NEW: Enhanced memory usage analysis
    , detailedUsageMap :: Map.Map Int TrackedProcessor.MemoryUsage  -- NEW: detailed usage tracking
    } deriving (Show)

-- | Detailed register usage breakdown
data DeadOperationAnalysis = DeadOperationAnalysis
    { deadR0Operations :: [Int]     -- Program positions with dead R0 operations
    , deadR1Operations :: [Int]     -- Program positions with dead R1 operations
    , r0ConsumptionStatus :: String -- Human readable status
    , r1ConsumptionStatus :: String -- Human readable status
    } deriving (Show, Eq)

-- Core instruction categories based on observable effects
registerManipulating :: [Byte]
registerManipulating = [1, 2, 3, 4, 5, 6, 9, 10]
-- Instructions that modify register values but have no direct observable effect
-- 1=ADD, 2=SUB, 3=INC_R0, 4=INC_R1, 5=DEC_R0, 6=DEC_R1, 9=LOAD_R0, 10=LOAD_R1

registerConsuming :: [Byte]
registerConsuming = [11, 12, 14, 15]
-- Instructions that use register values for observable effects (memory/control flow)
-- 11=STORE_R0, 12=STORE_R1, 14=JZ, 15=JNZ

nonRegisterInstructions :: [Byte]
nonRegisterInstructions = [0, 7, 8, 13]
-- Instructions that don't involve registers at all
-- 0=HALT, 7=NOP, 8=PRINT, 13=JMP

-- Register-specific operation categories
r0ManipulatingOnly :: [Byte]
r0ManipulatingOnly = [3, 5, 9]
-- Instructions that only manipulate R0: INC_R0, DEC_R0, LOAD_R0

r1ManipulatingOnly :: [Byte]
r1ManipulatingOnly = [4, 6, 10]
-- Instructions that only manipulate R1: INC_R1, DEC_R1, LOAD_R1

bothRegisterOperations :: [Byte]
bothRegisterOperations = [1, 2]
-- Instructions that manipulate both registers: ADD, SUB

r0ConsumingOnly :: [Byte]
r0ConsumingOnly = [11, 14, 15]
-- Instructions that only consume R0: STORE_R0, JZ, JNZ

r1ConsumingOnly :: [Byte]
r1ConsumingOnly = [12]
-- Instructions that only consume R1: STORE_R1

-- Derived categories for common use cases
deadCodeEquivalentInstructions :: [Byte]
deadCodeEquivalentInstructions = registerManipulating
-- When registers are never consumed, all register-manipulating instructions are equivalent

r0DeadCodeEquivalent :: [Byte]
r0DeadCodeEquivalent = r0ManipulatingOnly ++ bothRegisterOperations  -- [3, 5, 9, 1, 2]
-- When R0 is never consumed, these operations are equivalent

r1DeadCodeEquivalent :: [Byte]
r1DeadCodeEquivalent = r1ManipulatingOnly ++ bothRegisterOperations  -- [4, 6, 10, 1, 2]
-- When R1 is never consumed, these operations are equivalent

-- | Complete pattern analysis using already-executed TrackedDevice
analyzeProgram :: [Byte] -> TrackedDevice -> ProgramAnalysis
analyzeProgram program device =
    -- 1. Unused Memory Analysis
    let unusedMemory = identifyUnusedMemory program device

    -- 2. Dead Register Analysis
        (regAnalysis, deadPositions) = analyzeRegisterOperations program device

    -- 3. Enhanced Memory Usage Analysis
        memoryUsageAnalysis = analyzeMemoryUsage device

    -- 4. Extract detailed usage information
        detailedUsage = getDetailedUsage device

    in ProgramAnalysis
        { programOriginal = program
        , unusedMemoryPositions = unusedMemory
        , deadRegisterPositions = deadPositions
        , registerAnalysis = regAnalysis
        , trackedDevice = device
        , memoryAnalysis = memoryUsageAnalysis
        , detailedUsageMap = detailedUsage
        }

-- | Identify unused memory locations that can be wildcarded
identifyUnusedMemory :: [Byte] -> TrackedDevice -> [Int]
identifyUnusedMemory program device =
    let -- Consider all 16 memory locations available on the 4917 processor
        allMemoryLocations = [0..15]
        accessedLocs = Set.toList (getAccessedLocations device)
    in filter (`notElem` accessedLocs) allMemoryLocations

-- | Create wildcard pattern from program by marking unused locations
createMemoryWildcardPattern :: [Byte] -> TrackedDevice -> [Maybe Byte]
createMemoryWildcardPattern program device =
    let unusedPositions = Set.fromList (identifyUnusedMemory program device)
    in map (\(pos, byte) -> if pos `Set.member` unusedPositions
                           then Nothing  -- Wildcard
                           else Just byte) (zip [0..] program)

-- | Analyze register operations to identify dead code
analyzeRegisterOperations :: [Byte] -> TrackedDevice -> (DeadOperationAnalysis, [Int])
analyzeRegisterOperations program device =
    let r0Used = getR0WasConsumed device
        r1Used = getR1WasConsumed device
        r0HasCombination = getR0ContainsCombination device

        -- Identify all register-manipulating instruction positions
        regOpPositions = findRegisterManipulatingPositions program

        -- Classify dead operations based on consumption flags
        deadR0Ops = if not r0Used then findR0ManipulatingPositions program else []
        deadR1Ops = if not r1Used && not r0HasCombination then findR1ManipulatingPositions program
                   else if not r1Used && r0HasCombination then findR1OpsAfterCombination program
                   else []

        analysis = DeadOperationAnalysis
            { deadR0Operations = deadR0Ops
            , deadR1Operations = deadR1Ops
            , r0ConsumptionStatus = if r0Used then "Consumed" else "Never Used"
            , r1ConsumptionStatus = if r1Used then "Consumed"
                                   else if r0HasCombination then "Used in Combination"
                                   else "Never Used"
            }

    in (analysis, deadR0Ops ++ deadR1Ops)

-- | Find all positions of register-manipulating instructions
findRegisterManipulatingPositions :: [Byte] -> [Int]
findRegisterManipulatingPositions program =
    [pos | (pos, instr) <- zip [0..] program, instr `elem` registerManipulating]

-- | Find R0-specific manipulating instructions
findR0ManipulatingPositions :: [Byte] -> [Int]
findR0ManipulatingPositions program =
    let r0Manipulating = [1, 2, 3, 5, 9]  -- ADD, SUB, INC R0, DEC R0, LOAD R0
    in [pos | (pos, instr) <- zip [0..] program, instr `elem` r0Manipulating]

-- | Find R1-specific manipulating instructions
findR1ManipulatingPositions :: [Byte] -> [Int]
findR1ManipulatingPositions program =
    let r1Manipulating = [1, 2, 4, 6, 10]  -- ADD, SUB, INC R1, DEC R1, LOAD R1
    in [pos | (pos, instr) <- zip [0..] program, instr `elem` r1Manipulating]

-- | Handle complex case: R1 operations after combination
findR1OpsAfterCombination :: [Byte] -> [Int]
findR1OpsAfterCombination program =
    -- For now, return empty since this requires sophisticated execution flow analysis
    -- This would need to track when combinations occur and what R1 operations happen after
    []

-- | Analyze memory usage patterns using enhanced tracking
analyzeMemoryUsage :: TrackedDevice -> EnhancedMemoryAnalysis
analyzeMemoryUsage device =
    let instrLocs = Set.toList (getInstructionLocations device)
        operandLocs = Set.toList (getOperandLocations device)
        mixedLocs = Set.toList (getMixedUsageLocations device)
        instrOnlyLocs = Set.toList (getInstructionOnlyLocations device)
        operandOnlyLocs = Set.toList (getOperandOnlyLocations device)

        -- Classify each memory position
        usageTypes = map (classifyPositionUsageType instrLocs operandLocs mixedLocs) [0..15]

        -- Identify operand optimization opportunities
        operandOptimizations = findOperandOptimizations device operandOnlyLocs

    in EnhancedMemoryAnalysis usageTypes operandOptimizations

-- | Classify a single memory position's usage type
classifyPositionUsageType :: [Int] -> [Int] -> [Int] -> Int -> MemoryUsageType
classifyPositionUsageType instrLocs operandLocs mixedLocs pos
    | pos `elem` mixedLocs = MixedUsage
    | pos `elem` instrLocs = InstructionOnly
    | pos `elem` operandLocs = OperandOnly
    | otherwise = Unused

-- | Find operand positions that can be optimized by output length
findOperandOptimizations :: TrackedDevice -> [Int] -> [(Int, [Byte])]
findOperandOptimizations device operandOnlyLocs =
    let program = Vector.toList (getMemory device)
        optimizations = mapMaybe (analyzeOperandPosition program) operandOnlyLocs
    in optimizations

-- | Analyze a specific operand position for optimization opportunities
analyzeOperandPosition :: [Byte] -> Int -> Maybe (Int, [Byte])
analyzeOperandPosition program pos =
    if pos > 0 && pos < length program
    then case program !! (pos - 1) of
        8 -> -- PRINT instruction operand
            let currentValue = program !! pos
                currentOutputLength = if currentValue <= 9 then 1 else 2
                equivalentValues = if currentOutputLength == 1
                                  then singleCharOutput     -- All single-digit outputs
                                  else doubleCharOutput     -- All double-digit outputs
            in Just (pos, equivalentValues)
        _ -> Nothing  -- Other instruction operands aren't easily optimizable
    else Nothing

-- Output length categories for print operand optimization
singleCharOutput :: [Byte]
singleCharOutput = [0..9]

doubleCharOutput :: [Byte]
doubleCharOutput = [10..15]

-- | Apply optimizations based on analysis results
optimizeProgram :: ProgramAnalysis -> OptimizedProgram
optimizeProgram analysis =
    let program = programOriginal analysis

        -- Always create pattern for full 16-byte memory space using enhanced classification
        wildcardPattern = map (classifyEnhancedMemoryPosition analysis) [0..15]

    in OptimizedProgram
        { originalProgram = program
        , wildcardPattern = wildcardPattern
        , reductionFactor = calculateReductionFactor wildcardPattern
        , equivalenceClass = generateEquivalenceClass wildcardPattern
        , programAnalysis = analysis
        }

-- | Enhanced memory position classification using memory usage analysis
classifyEnhancedMemoryPosition :: ProgramAnalysis -> Int -> OptimizedInstruction
classifyEnhancedMemoryPosition analysis pos
    | pos >= 16 = error "Invalid memory position"
    | otherwise =
        let usageType = (memoryUsageTypes (memoryAnalysis analysis)) !! pos
            program = programOriginal analysis
            operandOptimizations = operandOutputOptimizations (memoryAnalysis analysis)
        in case usageType of
            Unused -> Wildcard
            MixedUsage -> Required (program !! pos)  -- Must be exact due to dual usage
            InstructionOnly ->
                if pos `elem` deadRegisterPositions analysis
                then classifyDeadRegisterPosition (program !! pos)
                else Required (program !! pos)
            OperandOnly ->
                case lookup pos operandOptimizations of
                    Just equivalentValues -> AnyOf equivalentValues  -- Optimize by output length
                    Nothing -> Required (program !! pos)            -- Default to required


-- | Classify each program position based on analysis
classifyPosition :: ProgramAnalysis -> (Int, Byte) -> OptimizedInstruction
classifyPosition analysis (pos, originalByte)
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos `elem` deadRegisterPositions analysis = classifyDeadRegisterPosition originalByte
    | otherwise = Required originalByte

-- | Handle dead register positions with instruction grouping
classifyDeadRegisterPosition :: Byte -> OptimizedInstruction
classifyDeadRegisterPosition originalByte
    | originalByte `elem` registerManipulating = AnyOf deadCodeEquivalentInstructions
    | otherwise = Required originalByte  -- Non-register instructions must stay as-is

-- | Calculate search space reduction factor
calculateReductionFactor :: [OptimizedInstruction] -> Double
calculateReductionFactor pattern =
    let totalOriginalSpace = 16 ^ length pattern  -- 16^n for original program
        reducedSpace = product (map instructionSpaceSize pattern)
        reductionFactor = fromIntegral totalOriginalSpace / fromIntegral reducedSpace
    in reductionFactor

instructionSpaceSize :: OptimizedInstruction -> Int
instructionSpaceSize instruction = case instruction of
    Required _ -> 1      -- Only one valid value
    Wildcard -> 16       -- All 16 values valid
    AnyOf options -> length options  -- Number of valid options

-- | Generate canonical equivalence class representation (cleaned up with range formatting)
generateEquivalenceClass :: [OptimizedInstruction] -> String
generateEquivalenceClass pattern =
    let classifyInstr instr = case instr of
            Required b -> show b
            Wildcard -> "*"
            AnyOf opts -> formatByteRange opts  -- Use clean range formatting
    in concatMap classifyInstr pattern

-- | Human-readable representation of an OptimizedInstruction with usage information
formatInstructionWithUsage :: Int -> OptimizedInstruction -> Map.Map Int TrackedProcessor.MemoryUsage -> String
formatInstructionWithUsage pos instr usageMap =
    let usageStr = formatUsageInfo (Map.lookup pos usageMap)
        instrStr = formatOptimizedInstruction pos instr
    in printf "%-50s %s" instrStr usageStr

-- | Format optimized instruction without usage info
formatOptimizedInstruction :: Int -> OptimizedInstruction -> String
formatOptimizedInstruction pos instr = case instr of
    Required b -> printf "%2d: Required    %d" pos b
    Wildcard -> printf "%2d: Wildcard    *" pos
    AnyOf opts ->
        let description = case opts of
                [0,1,2,3,4,5,6,7,8,9] -> "[0-9]"           -- Single-char outputs (special case)
                [10,11,12,13,14,15] -> "[10-15]"           -- Double-char outputs (special case)  
                [1,2,3,4,5,6,9,10] -> "[reg-ops]"          -- Register operations (special case)
                _ -> formatByteRange opts                   -- Use existing range formatting (fallback)
        in printf "%2d: AnyOf       %s" pos description

-- | Format usage information from MemoryUsage
formatUsageInfo :: Maybe TrackedProcessor.MemoryUsage -> String
formatUsageInfo Nothing = "Unused"
formatUsageInfo (Just usage) =
    "[Used as: " ++ formatUsageTypes (TrackedProcessor.usageTypes usage) ++ "]"

-- | Format list of usage types
formatUsageTypes :: [TrackedProcessor.UsageType] -> String
formatUsageTypes [] = "Never accessed"
formatUsageTypes [TrackedProcessor.UsedAsInstruction name] = "Instruction (" ++ name ++ ")"
formatUsageTypes [TrackedProcessor.UsedAsOperand instrName _] = "Operand for " ++ instrName
formatUsageTypes [TrackedProcessor.NeverAccessed] = "Never accessed"
formatUsageTypes multiple = intercalate " + " (map formatSingleUsage multiple)
  where
    formatSingleUsage (TrackedProcessor.UsedAsInstruction name) = "Instruction (" ++ name ++ ")"
    formatSingleUsage (TrackedProcessor.UsedAsOperand instrName _) = "Operand for " ++ instrName
    formatSingleUsage TrackedProcessor.NeverAccessed = "Never accessed"

-- | Human-readable representation of an OptimizedInstruction (legacy function)
formatInstruction :: Int -> OptimizedInstruction -> String
formatInstruction pos instr = case instr of
    Required b ->
        let instrName = case b of
                0 -> "HALT"
                1 -> "ADD"
                2 -> "SUB"
                3 -> "INC_R0"
                4 -> "INC_R1"
                5 -> "DEC_R0"
                6 -> "DEC_R1"
                7 -> "NOP"
                8 -> "PRINT"
                9 -> "LOAD_R0"
                10 -> "LOAD_R1"
                11 -> "STORE_R0"
                12 -> "STORE_R1"
                13 -> "JMP"
                14 -> "JZ"
                15 -> "JNZ"
                _ -> "DATA"
        in printf "%2d: Required    %s (%d)" pos instrName b

    Wildcard ->
        printf "%2d: Wildcard    Any value (0-15)" pos

    AnyOf opts ->
        let description = case opts of
                [0,1,2,3,4,5,6,7,8,9] -> "Single-char output (0-9)"
                [10,11,12,13,14,15] -> "Double-char output (10-15)"
                [1,2,3,4,5,6,9,10] -> "Register operations (dead code)"
                [0,7,8,13] -> "Non-register operations"
                [3,5,9] -> "R0 operations"
                [4,6,10] -> "R1 operations"
                [1,2] -> "Both-register operations"
                [11,12,14,15] -> "Register-consuming operations"
                _ -> "Custom set: " ++ show opts
            optsList = formatByteRange opts
        in printf "%2d: AnyOf       %s %s" pos description optsList

-- | Human-readable display of an OptimizedProgram
prettyPrintOptimizedProgram :: OptimizedProgram -> String
prettyPrintOptimizedProgram opt =
    let usageMap = detailedUsageMap (programAnalysis opt)
    in unlines $
        [ "╔══════════════════════════════════════════════════════════════════════════════════════╗"
        , "║                                 OPTIMIZED PROGRAM                                     ║"
        , "╠══════════════════════════════════════════════════════════════════════════════════════╣"
        , printf "║ Original Program: %-66s ║" (show $ originalProgram opt)
        , printf "║ Equivalence Class: %-65s ║" (equivalenceClass opt)
        , printf "║ Reduction Factor: %.2fx%-58s ║" (reductionFactor opt) ""
        , "╠══════════════════════════════════════════════════════════════════════════════════════╣"
        , "║                              WILDCARD PATTERN (16-byte)                              ║"
        , "╠══════════════════════════════════════════════════════════════════════════════════════╣"
        ] ++
        [ printf "║ %s ║" (padRight 84 (formatInstructionWithUsage i instr usageMap))
          | (i, instr) <- zip [0..] (wildcardPattern opt)
        ] ++
        [ "╚══════════════════════════════════════════════════════════════════════════════════════╝"
        , ""
        , "OPTIMIZATION SUMMARY:"
        , "• Required:  Must be exact value (critical for program correctness)"
        , "• Wildcard:  Any value 0-15 (unused memory locations)"
        , "• AnyOf:     Any value from specified set (equivalent instructions/operands)"
        , ""
        , printf "Search space reduction: %s → %s programs"
            (formatLargeNumber $ round $ 16 ** fromIntegral (length $ wildcardPattern opt))
            (formatLargeNumber $ fromIntegral $ product $ map instructionSpaceSize $ wildcardPattern opt)
        ]

-- | Helper function to pad string to specified width
padRight :: Int -> String -> String
padRight width str = take width (str ++ repeat ' ')

-- | Format large numbers with commas for readability
formatLargeNumber :: Integer -> String
formatLargeNumber n = reverse $ intercalate "," $ chunksOf 3 $ reverse $ show n

-- | Split list into chunks of specified size
chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = take n xs : chunksOf n (drop n xs)

-- | Format a list of bytes with range notation for readability
formatByteRange :: [Byte] -> String
formatByteRange [] = "[]"
formatByteRange bytes = "[" ++ intercalate ", " (formatByteRanges (sort bytes)) ++ "]"

-- | Format sorted list of bytes into ranges (legacy function - replaced by generic formatRanges)
formatByteRanges :: [Byte] -> [String]
formatByteRanges [] = []
formatByteRanges (x:xs) =
    let consecutive = x : takeWhile (\y -> y == x + fromIntegral (length (takeWhile (< y) (x:consecutive)))) xs
        simpleConsecutive = takeConsecutiveSequence [x] xs
        rangeStr = formatSingleRange simpleConsecutive
        remaining = drop (length simpleConsecutive - 1) xs
    in rangeStr : formatByteRanges remaining

-- | Take a consecutive sequence starting with the given list
takeConsecutiveSequence :: [Byte] -> [Byte] -> [Byte]
takeConsecutiveSequence acc [] = acc
takeConsecutiveSequence acc (y:ys)
    | y == last acc + 1 = takeConsecutiveSequence (acc ++ [y]) ys
    | otherwise = acc

-- | Format a single range of consecutive numbers
formatSingleRange :: [Byte] -> String
formatSingleRange [] = ""
formatSingleRange [x] = show x
formatSingleRange [x, y]
    | y == x + 1 = show x ++ "-" ++ show y
    | otherwise = show x ++ ", " ++ show y
formatSingleRange xs@(x:_)
    | isConsecutive xs = show x ++ "-" ++ show (last xs)
    | otherwise = intercalate ", " (map show xs)
  where
    isConsecutive [] = True
    isConsecutive [_] = True
    isConsecutive (a:b:rest) = (b == a + 1) && isConsecutive (b:rest)