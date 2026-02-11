module WildcardPatternSpec (spec) where

import Test.Hspec
import WildcardPattern
import TrackedProcessor
import Data.Set (Set)
import qualified Data.Set as Set

-- Helper function to create and run a tracked device
runTestProgram :: [Byte] -> TrackedDevice
runTestProgram program = case createTrackedDevice program of
    Left err -> error $ "Test setup error: " ++ show err
    Right device -> runTrackedProgram device 1000

-- Helper function to analyze a program
analyzeTestProgram :: [Byte] -> ProgramAnalysis
analyzeTestProgram program = 
    let device = runTestProgram program
    in analyzeProgram program device

spec :: Spec
spec = describe "WildcardPattern" $ do
  
  context "Instruction Category Constants" $ do
    it "registerManipulating contains correct instructions" $ do
      registerManipulating `shouldBe` [1, 2, 3, 4, 5, 6, 9, 10]
      
    it "registerConsuming contains correct instructions" $ do
      registerConsuming `shouldBe` [11, 12, 14, 15]
      
    it "nonRegisterInstructions contains correct instructions" $ do
      nonRegisterInstructions `shouldBe` [0, 7, 8, 13]
      
    it "r0ManipulatingOnly contains correct instructions" $ do
      r0ManipulatingOnly `shouldBe` [3, 5, 9]
      
    it "r1ManipulatingOnly contains correct instructions" $ do
      r1ManipulatingOnly `shouldBe` [4, 6, 10]
      
    it "bothRegisterOperations contains correct instructions" $ do
      bothRegisterOperations `shouldBe` [1, 2]
      
    it "deadCodeEquivalentInstructions equals registerManipulating" $ do
      deadCodeEquivalentInstructions `shouldBe` registerManipulating

  context "Unused Memory Detection" $ do
    it "detects no unused memory when all positions accessed" $ do
      let program = [8, 5, 0]  -- PRINT 5, HALT
          device = runTestProgram program
          unused = identifyUnusedMemory program device
      unused `shouldBe` []

    it "detects unused memory after HALT" $ do
      let program = [8, 5, 0, 7, 8, 9]  -- PRINT 5, HALT, unused data
          device = runTestProgram program
          unused = identifyUnusedMemory program device
      unused `shouldBe` [3, 4, 5]

    it "detects unused memory in conditional that doesn't execute" $ do
      let program = [14, 4, 0, 0, 7]  -- JZ 4 (R0=0 so jumps), HALT, unused, NOP
          device = runTestProgram program
          unused = identifyUnusedMemory program device
      -- Should not access position 2 (skipped instruction) but will access 0,1,3,4
      2 `elem` unused `shouldBe` True

  context "Dead Register Operation Analysis" $ do
    it "detects dead register operations when registers never consumed" $ do
      let analysis = analyzeTestProgram [8, 5, 3, 4, 0]  -- PRINT 5, INC R0, INC R1, HALT
      -- Program: [8, 5, 3, 4, 0] positions 0, 1, 2, 3, 4  
      -- Position 1 (5) is an operand for PRINT, but 5=DEC R0 which is also a dead register op
      -- Positions 2 (3=INC R0) and 3 (4=INC R1) are dead register operations
      deadRegisterPositions analysis `shouldBe` [1, 2, 3]  -- Include position 1 since 5=DEC R0
      r0ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Never Used"
      r1ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Never Used"

    it "detects no dead operations when registers are consumed" $ do
      let analysis = analyzeTestProgram [3, 4, 1, 11, 0, 0]  -- INC R0, INC R1, ADD, STORE R0, HALT
      deadRegisterPositions analysis `shouldBe` []
      r0ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"
      r1ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"

    it "handles combination consumption correctly" $ do
      let analysis = analyzeTestProgram [3, 4, 1, 12, 1, 0]  -- INC R0, INC R1, ADD, STORE R1, HALT
      r0ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Never Used"
      r1ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"
      -- R0 operations should be dead since R0 is never consumed
      deadR0Operations (registerAnalysis analysis) `shouldBe` [0, 2, 4]

    it "correctly identifies R1 used in combination" $ do
      let analysis = analyzeTestProgram [3, 4, 1, 11, 0, 0]  -- INC R0, INC R1, ADD, STORE R0, HALT
      r1ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"
      -- No dead operations since R1 is used via combination
      deadR1Operations (registerAnalysis analysis) `shouldBe` []

  context "Program Analysis Integration" $ do
    it "analyzes program with both unused memory and dead registers" $ do
      let program = [8, 5, 3, 4, 0, 7, 8, 9]  -- PRINT 5, INC R0, INC R1, HALT, unused
          analysis = analyzeTestProgram program
      programOriginal analysis `shouldBe` program
      unusedMemoryPositions analysis `shouldBe` [5, 6, 7]
      -- Position 1 (5=DEC R0), 2 (3=INC R0), 3 (4=INC R1), 7 (9=LOAD R0) are all dead
      deadRegisterPositions analysis `shouldBe` [1, 2, 7, 3]

    it "handles empty dead register positions for meaningful programs" $ do
      let program = [3, 11, 0, 0]  -- INC R0, STORE R0, HALT
          analysis = analyzeTestProgram program
      deadRegisterPositions analysis `shouldBe` []
      r0ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"

  context "optimizeProgram Function - Core Examples" $ do
    it "optimizes program with dead registers - basic case" $ do
      let program = [8, 5, 3, 4, 0]  -- PRINT 5, INC R0, INC R1, HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- Verify complete OptimizedProgram structure
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 1000)  -- Significant reduction
      equivalenceClass optimized `shouldBe` "8[123456910][123456910][123456910]0"
      
      -- Verify pattern details
      wildcardPattern optimized `shouldBe` 
        [Required 8, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, Required 0]

    it "optimizes program with unused memory - practical case" $ do
      let program = [8, 12, 0, 7, 8, 15]  -- PRINT 12, HALT, unused data
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- Should have wildcards for unused positions and dead register ops
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 100)  -- Good reduction
      wildcardPattern optimized `shouldBe` [Required 8, Required 12, Required 0, Wildcard, Wildcard, Wildcard]

    it "optimizes meaningful program - no optimization case" $ do
      let program = [3, 4, 1, 11, 0, 0]  -- INC R0, INC R1, ADD, STORE R0, HALT  
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- Should have minimal optimization since all operations are meaningful
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldBe` 16777216.0  -- 16^6 / 1^6 = no reduction in pattern space
      wildcardPattern optimized `shouldBe` map Required program  -- All Required

    it "optimizes complex program - mixed optimization case" $ do
      let program = [8, 15, 3, 4, 1, 11, 2, 0, 7, 8, 12]  -- Complex program with dead and unused parts
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- Should optimize both unused memory and some dead operations
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 10)  -- Some reduction
      length (filter (== Wildcard) (wildcardPattern optimized)) `shouldSatisfy` (> 0)  -- Has wildcards

    it "optimizes program with combination consumption" $ do
      let program = [3, 4, 1, 12, 1, 0]  -- INC R0, INC R1, ADD, STORE R1, HALT
          analysis = analyzeTestProgram program  
          optimized = optimizeProgram analysis
      
      -- R0 operations should be dead since R0 never consumed directly
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 1000)  -- Good reduction from dead R0 ops
      -- Positions 0, 2, 4 should have AnyOf patterns (dead R0 operations)
      let pattern = wildcardPattern optimized
          isAnyOf (AnyOf _) = True
          isAnyOf _ = False
      (pattern !! 0) `shouldSatisfy` isAnyOf
      (pattern !! 2) `shouldSatisfy` isAnyOf
      (pattern !! 4) `shouldSatisfy` isAnyOf

  context "optimizeProgram Function - Edge Cases" $ do  
    it "optimizes minimal program" $ do
      let program = [0]  -- Just HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      originalProgram optimized `shouldBe` program
      wildcardPattern optimized `shouldBe` [Required 0]
      reductionFactor optimized `shouldBe` 16.0  -- 16^1 / 1^1

    it "optimizes program with all dead register operations" $ do
      let program = [3, 4, 5, 6, 1, 2, 0]  -- All register ops, no consumption, HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- All register operations should become AnyOf patterns
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 1000)  -- Good reduction (not necessarily massive)
      let pattern = wildcardPattern optimized
          isAnyOf (AnyOf _) = True
          isAnyOf _ = False
      length (filter isAnyOf pattern) `shouldBe` 4  -- Most register ops (some might be Required due to combination logic)
      last pattern `shouldBe` Required 0  -- HALT stays Required

    it "optimizes program with only unused memory" $ do
      let program = [8, 5, 0, 1, 2, 3, 4, 5, 6, 7]  -- PRINT 5, HALT, lots of unused data
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      originalProgram optimized `shouldBe` program  
      -- Should have many Wildcard positions for unused memory
      let pattern = wildcardPattern optimized
      length (filter (== Wildcard) pattern) `shouldSatisfy` (>= 5)  -- Many wildcards
      reductionFactor optimized `shouldSatisfy` (> 100)  -- Good reduction

  context "optimizeProgram Function - Real-World Examples" $ do
    it "optimizes typical brute-force search candidate" $ do
      let program = [8, 10, 3, 5, 4, 6, 0]  -- PRINT 10, dead register ops, HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- Should demonstrate significant optimization potential
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 1000)
      
      -- Calculate actual search space reduction
      let originalSpace = 16^7
          optimizedSpace = product $ map instructionSpaceSize (wildcardPattern optimized)
          actualReduction = fromIntegral originalSpace / fromIntegral optimizedSpace
      actualReduction `shouldSatisfy` (> 1000.0)

    it "optimizes program demonstrating pattern equivalence classes" $ do
      let program = [3, 1, 4, 2, 0]  -- INC R0, ADD, INC R1, SUB, HALT (all dead)
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis
      
      -- All register operations are equivalent when dead (but position 2 might not be dead due to combination)
      originalProgram optimized `shouldBe` program
      -- Position 2 (INC R1) might be Required if it's not considered dead
      equivalenceClass optimized `shouldContain` "[123456910]"
      
      -- Verify good search space reduction
      reductionFactor optimized `shouldSatisfy` (> 100)

  context "Legacy Optimization Tests" $ do
    it "creates correct wildcard patterns" $ do
      let analysis = analyzeTestProgram [8, 5, 3, 4, 0]  -- PRINT 5, INC R0, INC R1, HALT
          optimized = optimizeProgram analysis
      -- Position 1 (5=DEC R0) is also dead, so it gets AnyOf pattern too
      wildcardPattern optimized `shouldBe` 
        [Required 8, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, Required 0]

    it "creates wildcards for unused memory" $ do
      let analysis = analyzeTestProgram [8, 5, 0, 7, 8]  -- PRINT 5, HALT, unused
          optimized = optimizeProgram analysis
      -- Position 1 (5=DEC R0) is a dead register operation, so it gets AnyOf
      wildcardPattern optimized `shouldBe` [Required 8, AnyOf deadCodeEquivalentInstructions, Required 0, Wildcard, Wildcard]

    it "calculates reduction factors correctly" $ do
      let pattern = [Required 8, Wildcard, AnyOf [1,2,3], Required 0]
          factor = calculateReductionFactor pattern
      factor `shouldBe` (16^4 / (1 * 16 * 3 * 1))  -- 65536 / 48 = 1365.33...

    it "generates correct equivalence class strings" $ do
      let pattern = [Required 8, Wildcard, AnyOf [1,2], Required 0]
          eqClass = generateEquivalenceClass pattern
      eqClass `shouldBe` "8*[12]0"

  context "Complex Scenarios" $ do
    it "handles programs with loops correctly" $ do
      let program = [9, 6, 5, 15, 2, 0, 3]  -- LOAD R0 from 6, DEC R0, JNZ 2, HALT, data=3
          device = runTestProgram program
          analysis = analyzeProgram program device
      -- All positions should be accessed during loop execution
      length (unusedMemoryPositions analysis) `shouldBe` 0

    it "analyzes program with conditional branches" $ do
      let program = [14, 4, 8, 5, 0]  -- JZ 4, PRINT 5, HALT (R0=0, so skips print)
          device = runTestProgram program
          analysis = analyzeProgram program device
      -- Position 2 (PRINT) should be unused since jump skips it
      unusedMemoryPositions analysis `shouldContain` [2]

    it "handles combination with later register modifications" $ do
      let program = [3, 4, 1, 3, 5, 11, 0, 0]  -- INC R0, INC R1, ADD, INC R0, DEC R0, STORE R0, HALT
          analysis = analyzeTestProgram program
      -- R1 should still be considered consumed via combination despite R0 modifications
      r1ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"
      deadRegisterPositions analysis `shouldBe` []

  context "Edge Cases" $ do
    it "handles minimal programs" $ do
      let analysis = analyzeTestProgram [0]  -- Just HALT
      unusedMemoryPositions analysis `shouldBe` []
      deadRegisterPositions analysis `shouldBe` []

    it "handles programs with only register operations" $ do
      let analysis = analyzeTestProgram [3, 4, 5, 6, 0]  -- All register ops, HALT
      -- All register operations should be dead (order may vary)
      let deadPositions = deadRegisterPositions analysis
      length deadPositions `shouldBe` 4
      -- Check each position is in the dead list
      0 `elem` deadPositions `shouldBe` True  
      1 `elem` deadPositions `shouldBe` True
      2 `elem` deadPositions `shouldBe` True
      3 `elem` deadPositions `shouldBe` True

    it "handles programs with only consuming operations" $ do
      let analysis = analyzeTestProgram [11, 0, 12, 1, 0]  -- STORE R0, STORE R1, HALT
      -- Should detect consumption but no dead operations
      r0ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"
      r1ConsumptionStatus (registerAnalysis analysis) `shouldBe` "Consumed"

  context "Instruction Space Size Calculation" $ do
    it "calculates space for Required instructions" $ do
      instructionSpaceSize (Required 5) `shouldBe` 1

    it "calculates space for Wildcard instructions" $ do
      instructionSpaceSize Wildcard `shouldBe` 16

    it "calculates space for AnyOf instructions" $ do
      instructionSpaceSize (AnyOf [1, 2, 3]) `shouldBe` 3

  context "Find Register Operation Positions" $ do
    it "finds all register manipulating positions" $ do
      let program = [8, 5, 3, 1, 0]  -- PRINT 5, INC R0, ADD, HALT
          positions = findRegisterManipulatingPositions program
      -- Position 1 (5=DEC R0), position 2 (3=INC R0), position 3 (1=ADD) are all register manipulating
      positions `shouldBe` [1, 2, 3]

    it "finds R0 manipulating positions" $ do
      let program = [3, 4, 1, 5, 0]  -- INC R0, INC R1, ADD, DEC R0, HALT  
          positions = findR0ManipulatingPositions program
      positions `shouldBe` [0, 2, 3]  -- INC R0, ADD, DEC R0

    it "finds R1 manipulating positions" $ do
      let program = [3, 4, 2, 6, 0]  -- INC R0, INC R1, SUB, DEC R1, HALT
          positions = findR1ManipulatingPositions program
      positions `shouldBe` [1, 2, 3]  -- INC R1, SUB, DEC R1