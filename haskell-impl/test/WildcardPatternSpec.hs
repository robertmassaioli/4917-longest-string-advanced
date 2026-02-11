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

  context "Optimization and Pattern Generation" $ do
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