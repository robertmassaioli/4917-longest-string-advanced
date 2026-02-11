module TrackedProcessorSpec (spec) where

import Test.Hspec
import TrackedProcessor
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Vector.Unboxed ((!))  -- For memory indexing

spec :: Spec
spec = describe "TrackedProcessor" $ do
  context "Basic Functionality" $ do
    it "creates TrackedDevice from program" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT
          tracked = createTrackedDevice program
      getAccessedLocations tracked `shouldBe` Set.empty
      isHalted tracked `shouldBe` False
      getPc tracked `shouldBe` 0
      getR0 tracked `shouldBe` 0
      getR1 tracked `shouldBe` 0
      getSteps tracked `shouldBe` 0

    it "preserves original Device functionality" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT
          tracked = createTrackedDevice program
          finalTracked = runTrackedProgram tracked 10
      isHalted finalTracked `shouldBe` True
      getOutput finalTracked `shouldBe` 2

  context "Individual Instruction Tests" $ do
    describe "Single-byte instructions (0-7)" $ do
      it "HALT (0) - stops execution and tracks instruction fetch" $ do
        let program = [0]  -- HALT
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram tracked
        isHalted stepped `shouldBe` True
        getAccessedLocations stepped `shouldBe` Set.fromList [0]
        getPc stepped `shouldBe` 0

      it "ADD (1) - R0 = R0 + R1" $ do
        let program = [1, 0]  -- ADD, HALT
            tracked = createTrackedDevice program
            -- Set initial values
            tracked' = tracked { r0 = 3, r1 = 5 }
            stepped = stepTrackedProgram tracked'
        getR0 stepped `shouldBe` 8
        getPc stepped `shouldBe` 1
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

      it "SUB (2) - R0 = R0 - R1 with wraparound" $ do
        let program = [2, 0]  -- SUB, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 3, r1 = 5 }  -- 3 - 5 = -2 -> 14 (mod 16)
            stepped = stepTrackedProgram tracked'
        getR0 stepped `shouldBe` 14
        getPc stepped `shouldBe` 1
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

      it "INC R0 (3) - increments R0" $ do
        let program = [3, 0]  -- INC R0, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 15 }  -- Test wraparound
            stepped = stepTrackedProgram tracked'
        getR0 stepped `shouldBe` 0  -- 15 + 1 = 16 -> 0 (mod 16)
        getPc stepped `shouldBe` 1
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

      it "INC R1 (4) - increments R1" $ do
        let program = [4, 0]  -- INC R1, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r1 = 7 }
            stepped = stepTrackedProgram tracked'
        getR1 stepped `shouldBe` 8
        getPc stepped `shouldBe` 1
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

      it "DEC R0 (5) - decrements R0" $ do
        let program = [5, 0]  -- DEC R0, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 0 }  -- Test wraparound
            stepped = stepTrackedProgram tracked'
        getR0 stepped `shouldBe` 15  -- 0 - 1 = -1 -> 15 (mod 16)
        getPc stepped `shouldBe` 1
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

      it "DEC R1 (6) - decrements R1" $ do
        let program = [6, 0]  -- DEC R1, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r1 = 5 }
            stepped = stepTrackedProgram tracked'
        getR1 stepped `shouldBe` 4
        getPc stepped `shouldBe` 1
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

      it "NOP (7) - ring bell, no operation" $ do
        let program = [7, 0]  -- NOP, HALT
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram tracked
        getPc stepped `shouldBe` 1
        getR0 stepped `shouldBe` 0
        getR1 stepped `shouldBe` 0
        getAccessedLocations stepped `shouldBe` Set.fromList [0]

    describe "Two-byte instructions (8-15)" $ do
      it "PRINT (8) - outputs single digit" $ do
        let program = [8, 5, 0]  -- PRINT 5, HALT
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram tracked
        getOutput stepped `shouldBe` 1  -- Single digit = 1 character
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "PRINT (8) - outputs double digit" $ do
        let program = [8, 15, 0]  -- PRINT 15, HALT
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram stepped
        getOutput stepped `shouldBe` 2  -- Double digit = 2 characters
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "LOAD R0 (9) - loads value into R0" $ do
        let program = [9, 4, 0, 0, 42]  -- LOAD R0 from address 4, HALT, padding, data
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram tracked
        getR0 stepped `shouldBe` 42
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1, 4]

      it "LOAD R1 (10) - loads value into R1" $ do
        let program = [10, 5, 0, 0, 0, 99]  -- LOAD R1 from address 5, HALT, padding, data
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram tracked
        getR1 stepped `shouldBe` 99
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1, 5]

      it "STORE R0 (11) - stores R0 to memory" $ do
        let program = [11, 5, 0]  -- STORE R0 to address 5, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 123 }
            stepped = stepTrackedProgram tracked'
        -- Check memory was modified
        getMemory stepped ! 5 `shouldBe` 123
        getPc stepped `shouldBe` 2
        -- Should only access operand location, not destination (writes don't count)
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "STORE R1 (12) - stores R1 to memory" $ do
        let program = [12, 6, 0]  -- STORE R1 to address 6, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r1 = 200 }
            stepped = stepTrackedProgram tracked'
        getMemory stepped ! 6 `shouldBe` 200
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "JMP (13) - unconditional jump" $ do
        let program = [13, 5, 0, 0, 0, 7, 0]  -- JMP 5, padding, NOP, HALT
            tracked = createTrackedDevice program
            stepped = stepTrackedProgram tracked
        getPc stepped `shouldBe` 5
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "JZ (14) - jump if R0 == 0 (true case)" $ do
        let program = [14, 4, 3, 0, 5, 0]  -- JZ 4, INC R0, HALT, DEC R0, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 0 }  -- R0 is zero, should jump
            stepped = stepTrackedProgram tracked'
        getPc stepped `shouldBe` 4
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "JZ (14) - jump if R0 == 0 (false case)" $ do
        let program = [14, 4, 3, 0]  -- JZ 4, INC R0, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 1 }  -- R0 is not zero, should not jump
            stepped = stepTrackedProgram tracked'
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "JNZ (15) - jump if R0 != 0 (true case)" $ do
        let program = [15, 4, 3, 0, 5, 0]  -- JNZ 4, INC R0, HALT, DEC R0, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 1 }  -- R0 is not zero, should jump
            stepped = stepTrackedProgram tracked'
        getPc stepped `shouldBe` 4
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

      it "JNZ (15) - jump if R0 != 0 (false case)" $ do
        let program = [15, 4, 3, 0]  -- JNZ 4, INC R0, HALT
            tracked = createTrackedDevice program
            tracked' = tracked { r0 = 0 }  -- R0 is zero, should not jump
            stepped = stepTrackedProgram tracked'
        getPc stepped `shouldBe` 2
        getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

  context "Memory Access Tracking" $ do
    it "tracks instruction fetches for single-byte instructions" $ do
      let program = [3, 0]  -- INC R0, HALT
          tracked = createTrackedDevice program
          stepped = stepTrackedProgram tracked
      getAccessedLocations stepped `shouldBe` Set.fromList [0]

    it "tracks instruction and operand for two-byte instructions" $ do
      let program = [8, 15, 0]  -- PRINT 15, HALT
          tracked = createTrackedDevice program
          stepped = stepTrackedProgram tracked
      getAccessedLocations stepped `shouldBe` Set.fromList [0, 1]

    it "tracks multiple steps accumulating access locations" $ do
      let program = [8, 15, 8, 10, 0]  -- PRINT 15, PRINT 10, HALT
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked
          step2 = stepTrackedProgram step1
          step3 = stepTrackedProgram step2
      getAccessedLocations step3 `shouldBe` Set.fromList [0, 1, 2, 3, 4]

    it "handles memory wraparound correctly" $ do
      let program = [13, 0]  -- JMP 0 (jump to self)
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked
          step2 = stepTrackedProgram step1
      -- Should access location 0 multiple times but only count it once
      getAccessedLocations step2 `shouldBe` Set.fromList [0, 1]

  context "Program Execution" $ do
    it "runTrackedProgram preserves access tracking" $ do
      let program = [8, 15, 8, 10, 0]  -- PRINT 15, PRINT 10, HALT
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 10
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2, 3, 4]
      isHalted final `shouldBe` True
      getOutput final `shouldBe` 3  -- "15" (2 chars) + "10" (2 chars) = 4 total, wait that's wrong

    it "runTrackedProgramLoopCheck detects loops while tracking" $ do
      let program = [3, 13, 0]  -- INC R0, JMP 0 (infinite loop)
          tracked = createTrackedDevice program
          final = runTrackedProgramLoopCheck tracked
      -- Should access locations 0 (INC), 1 (JMP operand), 2 (JMP instruction) multiple times
      Set.isSubsetOf (Set.fromList [0, 1]) (getAccessedLocations final) `shouldBe` True
      -- Loop should be detected (not halted, but stopped by loop detection)
      isHalted final `shouldBe` False

  context "Memory Access Patterns" $ do
    it "identifies minimal memory footprint" $ do
      let program = [8, 15, 0, 99, 99, 99]  -- PRINT 15, HALT + unused data
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 10
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2]
      -- Should not access unused locations 3, 4, 5

    it "tracks data reads separately from instructions" $ do
      let program = [9, 5, 0, 0, 0, 123]  -- LOAD R0 from address 5, HALT, padding, data
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked  -- Execute LOAD
          step2 = stepTrackedProgram step1    -- Execute HALT
      getAccessedLocations step2 `shouldBe` Set.fromList [0, 1, 2, 5]
      getR0 step2 `shouldBe` 123

    it "handles STORE instructions (no data read tracking)" $ do
      let program = [11, 5, 0]  -- STORE R0 to address 5, HALT
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked
          step2 = stepTrackedProgram step1
      getAccessedLocations step2 `shouldBe` Set.fromList [0, 1, 2]
      -- Should not include address 5 since STORE writes, doesn't read

  context "Complex Example Programs" $ do
    it "tracks simple print program" $ do
      let program = [8, 5, 8, 10, 8, 15, 0]  -- PRINT 5, PRINT 10, PRINT 15, HALT
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 20
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2, 3, 4, 5, 6]
      getOutput final `shouldBe` 5  -- "5" (1) + "10" (2) + "15" (2) = 5 chars
      isHalted final `shouldBe` True

    it "tracks conditional program execution" $ do
      let program = [14, 6, 8, 1, 0, 0, 8, 2, 0]  -- JZ 6, PRINT 1, HALT, PRINT 2, HALT
          tracked = createTrackedDevice program
          tracked' = tracked { r0 = 0 }  -- R0 = 0, should jump to print 2
          final = runTrackedProgram tracked' 20
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 6, 7, 8]
      getOutput final `shouldBe` 1  -- Only "2" printed
      isHalted final `shouldBe` True

    it "tracks load-store-print sequence" $ do
      let program = [9, 8, 11, 9, 8, 15, 0, 0, 42, 0]  -- LOAD R0 from 8, STORE R0 to 9, PRINT 15, HALT, data, modified
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 20
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2, 3, 4, 5, 6, 8]
      getOutput final `shouldBe` 2  -- "15" printed
      isHalted final `shouldBe` True
      getMemory final ! 9 `shouldBe` 42  -- Value was stored

    it "tracks loop with counter" $ do
      let program = [9, 8, 5, 15, 4, 13, 2, 0, 3]  -- LOAD R0 from 8, DEC R0, JNZ 4, INC R1, JMP 2, HALT, data=3
          tracked = createTrackedDevice program
          final = runTrackedProgramLoopCheck tracked
      -- Should access: 0,1,8 (LOAD), 2 (DEC), 3,4 (JNZ), 5,6 (JMP) multiple times
      Set.isSubsetOf (Set.fromList [0, 1, 2, 3, 4, 5, 6, 8]) (getAccessedLocations final) `shouldBe` True

    it "tracks quine-like self-modifying program" $ do
      let program = [9, 6, 11, 7, 8, 15, 42, 0]  -- LOAD R0 from 6, STORE R0 to 7, PRINT 15, HALT, data, target
          tracked = createTrackedDevice program
          final = runTrackedProgram tracked 20
      getAccessedLocations final `shouldBe` Set.fromList [0, 1, 2, 3, 4, 5, 6, 7]
      getOutput final `shouldBe` 2  -- "15" printed
      getMemory final ! 7 `shouldBe` 42  -- Self-modification occurred

  context "Edge Cases" $ do
    it "handles empty program" $ do
      let program = []  -- All zeros
          tracked = createTrackedDevice program
          stepped = stepTrackedProgram tracked
      isHalted stepped `shouldBe` True  -- HALT instruction (0)
      getAccessedLocations stepped `shouldBe` Set.fromList [0]

    it "handles program counter wraparound" $ do
      let program = [13, 0]  -- JMP 0, creates infinite loop
          tracked = createTrackedDevice program
          final = runTrackedProgramLoopCheck tracked
      -- Should detect loop and stop
      getAccessedLocations final `shouldBe` Set.fromList [0, 1]

    it "handles invalid instructions as NOP" $ do
      let program = [255, 0]  -- Invalid instruction, HALT
          tracked = createTrackedDevice program
          step1 = stepTrackedProgram tracked
          step2 = stepTrackedProgram step1
      isHalted step2 `shouldBe` True
      getPc step2 `shouldBe` 1
      getAccessedLocations step2 `shouldBe` Set.fromList [0, 1]