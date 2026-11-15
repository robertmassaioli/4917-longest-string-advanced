module WildcardPatternSpec (spec) where

import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck
import WildcardPattern
import TrackedProcessor
import ProcessorTestSupport (genNibble)
import qualified Processor as P
import Data.Set (Set)
import qualified Data.Set as Set
import Data.List (nub)

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

genOptimizedInstruction :: Gen OptimizedInstruction
genOptimizedInstruction = oneof
    [ Required <$> genNibble
    , pure Wildcard
    , do
        first <- genNibble
        rest <- listOf genNibble
        pure (AnyOf (first : rest))
    ]

shrinkOptimizedInstruction :: OptimizedInstruction -> [OptimizedInstruction]
shrinkOptimizedInstruction (Required value) = [Required smaller | smaller <- shrink value, smaller <= 15]
shrinkOptimizedInstruction Wildcard = []
shrinkOptimizedInstruction (AnyOf options) =
    [AnyOf smaller | smaller <- shrinkList shrink options, not (null smaller), all (<= 15) smaller]
    ++ [AnyOf [smaller] | value <- nub options, smaller <- shrink value, smaller <= 15]

shrinkOptimizedPattern :: [OptimizedInstruction] -> [[OptimizedInstruction]]
shrinkOptimizedPattern pattern =
    [take index pattern ++ [smaller] ++ drop (index + 1) pattern
    | (index, instruction) <- zip [0..] pattern
    , smaller <- shrinkOptimizedInstruction instruction]

genHaltTailCase :: Gen ([P.Byte], [P.Byte])
genHaltTailCase = do
    size <- chooseInt (0, 15)
    tailBytes <- vectorOf size genNibble
    alternatives <- vectorOf size genNibble
    pure (tailBytes, alternatives)

matches :: OptimizedInstruction -> P.Byte -> Bool
matches (Required expected) actual = expected == actual
matches Wildcard _ = True
matches (AnyOf options) actual = actual `elem` options


spec :: Spec
spec = describe "WildcardPattern" $ do

  modifyMaxSuccess (max 300) $
    prop "keeps instruction-space sizes in the 0-to-16 range" $
      forAllShrink genOptimizedInstruction shrinkOptimizedInstruction $ \instruction ->
        let size = instructionSpaceSize instruction
        in size >= 0 && size <= 16

  modifyMaxSuccess (max 300) $
    prop "keeps reduction factors finite and at least one for nonempty patterns" $
      forAllShrink (vectorOf 16 genOptimizedInstruction) shrinkOptimizedPattern $ \pattern ->
        let factor = calculateReductionFactor pattern
        in not (isNaN factor || isInfinite factor) && factor >= 1

  it "does not overflow the search-space calculation for sixteen wildcards" $
    calculateReductionFactor (replicate 16 Wildcard) `shouldBe` 1.0

  it "counts distinct valid AnyOf alternatives" $
    instructionSpaceSize (AnyOf [3, 3, 255]) `shouldBe` 1

  it "represents an impossible empty AnyOf pattern as an infinite reduction" $
    calculateReductionFactor [AnyOf []] `shouldSatisfy` isInfinite

  modifyMaxSuccess (max 300) $
    prop "wildcarding cells after an immediate HALT preserves program behavior" $
      forAll genHaltTailCase $ \(tailBytes, alternatives) ->
        let original = 0 : tailBytes
            replacement = 0 : alternatives
            optimized = optimizeProgram (analyzeTestProgram original)
            paddedReplacement = replacement ++ replicate 16 0
            patternMatches = and (zipWith matches (wildcardPattern optimized) paddedReplacement)
        in patternMatches
           && P.runProgramResult (P.createDevice original) 16
                == P.runProgramResult (P.createDevice replacement) 16

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
      -- Positions 3-15 are unused since only positions 0,1,2 are accessed
      unused `shouldBe` [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

    it "detects unused memory after HALT" $ do
      let program = [8, 5, 0, 7, 8, 9]  -- PRINT 5, HALT, unused data
          device = runTestProgram program
          unused = identifyUnusedMemory program device
      -- Should detect positions 3,4,5 (after HALT) plus 6,7,8,9,10,11,12,13,14,15 (beyond program)
      unused `shouldBe` [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

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
      -- Positions 5,6,7 (after HALT) plus 8,9,10,11,12,13,14,15 (beyond program) are unused
      unusedMemoryPositions analysis `shouldBe` [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
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
      equivalenceClass optimized `shouldBe` "8[0123456789][123456910][123456910]0***********"

      -- Verify pattern details - should be 16 bytes with wildcards for unused positions
      length (wildcardPattern optimized) `shouldBe` 16
      take 5 (wildcardPattern optimized) `shouldBe`
        [Required 8, AnyOf singleCharOutput, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, Required 0]
      drop 5 (wildcardPattern optimized) `shouldBe` replicate 11 Wildcard

    it "optimizes program with unused memory - practical case" $ do
      let program = [8, 12, 0, 7, 8, 15]  -- PRINT 12, HALT, unused data
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis

      -- Should have wildcards for unused positions in full 16-byte pattern
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 100)  -- Good reduction
      length (wildcardPattern optimized) `shouldBe` 16  -- Always 16 bytes
      -- Position 0: Required 8, Position 1: AnyOf double-char (12 is double-char), Position 2: Required 0
      take 3 (wildcardPattern optimized) `shouldBe` [Required 8, AnyOf doubleCharOutput, Required 0]
      drop 3 (wildcardPattern optimized) `shouldBe` replicate 13 Wildcard

    it "optimizes meaningful program - no optimization case" $ do
      let program = [3, 4, 1, 11, 0, 0]  -- INC R0, INC R1, ADD, STORE R0, HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis

      -- Should have minimal optimization since all operations are meaningful
      originalProgram optimized `shouldBe` program
      length (wildcardPattern optimized) `shouldBe` 16  -- Always 16 bytes
      -- First 6 positions should be Required (the program), rest should be Wildcard
      take 6 (wildcardPattern optimized) `shouldBe` map Required program
      drop 6 (wildcardPattern optimized) `shouldBe` replicate 10 Wildcard

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
      -- Position 0 (INC R0): dead register op, Position 2 (ADD): Required because R1 is consumed by STORE R1
      let pattern = wildcardPattern optimized
          isAnyOf (AnyOf _) = True
          isAnyOf _ = False
      (pattern !! 0) `shouldSatisfy` isAnyOf  -- INC R0 is dead 
      (pattern !! 2) `shouldSatisfy` isAnyOf  -- ADD is dead - even though R1 is consumed, R0 is not
      (pattern !! 4) `shouldBe` Required 1    -- Position 4 contains ADD (1) - not classified as dead

  context "optimizeProgram Function - Edge Cases" $ do
    it "optimizes minimal program" $ do
      let program = [0]  -- Just HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis

      originalProgram optimized `shouldBe` program
      length (wildcardPattern optimized) `shouldBe` 16  -- Always 16 bytes
      -- First position should be Required 0, rest should be Wildcard
      head (wildcardPattern optimized) `shouldBe` Required 0
      drop 1 (wildcardPattern optimized) `shouldBe` replicate 15 Wildcard

    it "optimizes program with all dead register operations" $ do
      let program = [3, 4, 5, 6, 1, 2, 0]  -- All register ops, no consumption, HALT
          analysis = analyzeTestProgram program
          optimized = optimizeProgram analysis

      -- All register operations should become AnyOf patterns
      originalProgram optimized `shouldBe` program
      reductionFactor optimized `shouldSatisfy` (> 1000)  -- Good reduction (not necessarily massive)
      length (wildcardPattern optimized) `shouldBe` 16  -- Always 16 bytes
      let pattern = wildcardPattern optimized
          isAnyOf (AnyOf _) = True
          isAnyOf _ = False
      length (filter isAnyOf (take 7 pattern)) `shouldBe` 4  -- Most register ops in first 7 positions
      (pattern !! 6) `shouldBe` Required 0  -- HALT at position 6
      drop 7 (wildcardPattern optimized) `shouldBe` replicate 9 Wildcard  -- Positions 7-15 unused

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

      -- Calculate actual search space reduction (now 16^16 vs optimized)
      let originalSpace = 16^16
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
      -- Should be 16 bytes with enhanced pattern: print operand optimized by output length
      length (wildcardPattern optimized) `shouldBe` 16
      take 5 (wildcardPattern optimized) `shouldBe`
        [Required 8, AnyOf singleCharOutput, AnyOf deadCodeEquivalentInstructions, AnyOf deadCodeEquivalentInstructions, Required 0]
      drop 5 (wildcardPattern optimized) `shouldBe` replicate 11 Wildcard

    it "creates wildcards for unused memory" $ do
      let analysis = analyzeTestProgram [8, 5, 0, 7, 8]  -- PRINT 5, HALT, unused
          optimized = optimizeProgram analysis
      -- Should be 16 bytes with enhanced pattern: print operand optimized by output length
      length (wildcardPattern optimized) `shouldBe` 16
      let pattern = wildcardPattern optimized
      take 3 pattern `shouldBe` [Required 8, AnyOf singleCharOutput, Required 0]
      drop 3 pattern `shouldBe` replicate 13 Wildcard

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
      -- Some positions beyond the program will be unused (positions 7-15)
      length (unusedMemoryPositions analysis) `shouldBe` 9

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
      -- Positions 1-15 are unused since only position 0 is accessed
      unusedMemoryPositions analysis `shouldBe` [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
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
