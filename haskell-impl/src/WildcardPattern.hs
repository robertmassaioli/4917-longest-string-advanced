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
    ) where

import TrackedProcessor
import Data.Set (Set)
import qualified Data.Set as Set

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
    } deriving (Show)

-- | Complete analysis results for a program
data ProgramAnalysis = ProgramAnalysis
    { programOriginal :: [Byte]
    , unusedMemoryPositions :: [Int]
    , deadRegisterPositions :: [Int]  
    , registerAnalysis :: DeadOperationAnalysis
    , trackedDevice :: TrackedDevice
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
    
    in ProgramAnalysis
        { programOriginal = program
        , unusedMemoryPositions = unusedMemory  
        , deadRegisterPositions = deadPositions
        , registerAnalysis = regAnalysis
        , trackedDevice = device
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

-- | Apply optimizations based on analysis results
optimizeProgram :: ProgramAnalysis -> OptimizedProgram
optimizeProgram analysis = 
    let program = programOriginal analysis
        
        -- Always create pattern for full 16-byte memory space
        wildcardPattern = map (classifyMemoryPosition analysis) [0..15]
            
    in OptimizedProgram
        { originalProgram = program
        , wildcardPattern = wildcardPattern  
        , reductionFactor = calculateReductionFactor wildcardPattern
        , equivalenceClass = generateEquivalenceClass wildcardPattern
        }

-- | Classify each memory position based on analysis (for full 16-byte space)
classifyMemoryPosition :: ProgramAnalysis -> Int -> OptimizedInstruction  
classifyMemoryPosition analysis pos 
    | pos `elem` unusedMemoryPositions analysis = Wildcard
    | pos `elem` deadRegisterPositions analysis = 
        let program = programOriginal analysis
        in if pos < length program
           then classifyDeadRegisterPosition (program !! pos)
           else Wildcard  -- Beyond program length
    | pos < length (programOriginal analysis) = 
        Required ((programOriginal analysis) !! pos)
    | otherwise = Wildcard  -- Beyond program length

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

-- | Generate canonical equivalence class representation
generateEquivalenceClass :: [OptimizedInstruction] -> String
generateEquivalenceClass pattern = 
    let classifyInstr instr = case instr of
            Required b -> show b
            Wildcard -> "*"
            AnyOf opts -> "[" ++ concatMap show opts ++ "]"
    in concatMap classifyInstr pattern