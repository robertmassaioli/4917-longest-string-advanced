module ProcessorSpec (spec) where

import Test.Hspec
import Test.Hspec.QuickCheck
import Processor
import Data.Vector.Unboxed ((!))

-- | Convert legacy tests to Hspec format while maintaining exact same pass/fail behavior
spec :: Spec
spec = describe "Processor" $ do
  context "Individual Instructions" $ do
    it "HALT - basic halt" $ do
      let device = createDevice [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          result = runStep device
      isHalted result `shouldBe` True
      getOutput result `shouldBe` 0
    
    it "ADD - basic addition" $ do
      let device = createDevice [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 3, r1 = 5 }
          result = runStep device'
      r0 result `shouldBe` 8
      
    it "ADD - overflow wrapping" $ do
      let device = createDevice [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 15, r1 = 2 }
          result = runStep device'
      r0 result `shouldBe` 1  -- (15 + 2) mod 16 = 1
      
    it "SUB - basic subtraction" $ do
      let device = createDevice [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 8, r1 = 3 }
          result = runStep device'
      r0 result `shouldBe` 5
      
    it "SUB - underflow wrapping" $ do
      let device = createDevice [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 2, r1 = 5 }
          result = runStep device'
      r0 result `shouldBe` 13  -- (2 - 5) mod 16 = 13
      
    it "INC R0 - basic increment" $ do
      let device = createDevice [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 5 }
          result = runStep device'
      r0 result `shouldBe` 6
      
    it "INC R0 - overflow wrap" $ do
      let device = createDevice [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 15 }
          result = runStep device'
      r0 result `shouldBe` 0
      
    it "INC R1 - basic increment" $ do
      let device = createDevice [4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r1 = 7 }
          result = runStep device'
      r1 result `shouldBe` 8
      
    it "DEC R0 - basic decrement" $ do
      let device = createDevice [5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 5 }
          result = runStep device'
      r0 result `shouldBe` 4
      
    it "DEC R0 - underflow wrap" $ do
      let device = createDevice [5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 0 }
          result = runStep device'
      r0 result `shouldBe` 15
      
    it "DEC R1 - basic decrement" $ do
      let device = createDevice [6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r1 = 3 }
          result = runStep device'
      r1 result `shouldBe` 2
      
    it "NOP - no operation" $ do
      let device = createDevice [7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 5, r1 = 3 }
          result = runStep device'
      r0 result `shouldBe` 5
      r1 result `shouldBe` 3
      pc result `shouldBe` 1
      
    it "OUTPUT - single digit" $ do
      let device = createDevice [8, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          result = runStep device
      getOutput result `shouldBe` 1
      
    it "OUTPUT - double digit" $ do
      let device = createDevice [8, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          result = runStep device
      getOutput result `shouldBe` 2
      
    it "LOAD R0 - basic load" $ do
      let device = createDevice [9, 5, 0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          result = runStep device
      r0 result `shouldBe` 42
      
    it "LOAD R1 - basic load" $ do
      let device = createDevice [10, 3, 0, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          result = runStep device
      r1 result `shouldBe` 13
      
    it "STORE R0 - basic store" $ do
      let device = createDevice [11, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 25 }
          result = runStep device'
      (memory result) ! 7 `shouldBe` 25
      
    it "STORE R1 - basic store" $ do
      let device = createDevice [12, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r1 = 33 }
          result = runStep device'
      (memory result) ! 4 `shouldBe` 33
      
    it "JMP - unconditional jump" $ do
      let device = createDevice [13, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          result = runStep device
      pc result `shouldBe` 8
      
    it "JZ - jump when zero" $ do
      let device = createDevice [14, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 0 }
          result = runStep device'
      pc result `shouldBe` 5
      
    it "JZ - no jump when non-zero" $ do
      let device = createDevice [14, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 3 }
          result = runStep device'
      pc result `shouldBe` 2
      
    it "JNZ - jump when non-zero" $ do
      let device = createDevice [15, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 7 }
          result = runStep device'
      pc result `shouldBe` 12
      
    it "JNZ - no jump when zero" $ do
      let device = createDevice [15, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          device' = device { r0 = 0 }
          result = runStep device'
      pc result `shouldBe` 2

  context "Complete Programs" $ do
    it "Simple Counter" $ do
      let program = [3, 3, 3, 0]  -- INC R0 three times, then HALT
          device = createDevice (program ++ repeat 0)
          finalDevice = runProgramLimited device 10
      r0 finalDevice `shouldBe` 3
      isHalted finalDevice `shouldBe` True
      
    it "Output Program" $ do
      let program = [8, 15, 8, 10, 0]  -- OUTPUT 15, OUTPUT 10, HALT
          device = createDevice (program ++ repeat 0)
          finalDevice = runProgramLimited device 10
      getOutput finalDevice `shouldBe` 4  -- "15" (2 chars) + "10" (2 chars) = 4
      isHalted finalDevice `shouldBe` True
      
    it "Arithmetic Program" $ do
      let program = [3, 4, 1, 0]  -- INC R0, INC R1, ADD, HALT
          device = createDevice (program ++ repeat 0)
          finalDevice = runProgramLimited device 10
      r0 finalDevice `shouldBe` 2  -- 1 + 1 = 2
      isHalted finalDevice `shouldBe` True
      
    it "Conditional Jump - Zero" $ do
      let program = [14, 4, 3, 0, 5, 0]  -- JZ 4, INC R0, HALT, DEC R0, HALT
          device = createDevice (program ++ repeat 0)
          device' = device { r0 = 0 }  -- R0 starts at 0
          finalDevice = runProgramLimited device' 10
      r0 finalDevice `shouldBe` 15  -- Should jump to DEC R0, making R0 = 255 wrapped to 15
      isHalted finalDevice `shouldBe` True
      
    it "Conditional Jump - Non-Zero" $ do
      let program = [14, 4, 3, 0, 5, 0]  -- JZ 4, INC R0, HALT, DEC R0, HALT
          device = createDevice (program ++ repeat 0)
          device' = device { r0 = 1 }  -- R0 starts at 1
          finalDevice = runProgramLimited device' 10
      r0 finalDevice `shouldBe` 2  -- Should not jump, execute INC R0, making R0 = 2
      isHalted finalDevice `shouldBe` True
      
    it "Simple Loop" $ do
      let program = [3, 13, 0]  -- INC R0, JMP 0 (infinite loop)
          device = createDevice (program ++ repeat 0)
          finalDevice = runProgramLimited device 5  -- Limited steps
      -- The loop is: INC R0 (at PC=0), JMP 0 (at PC=1), repeat
      -- Each iteration increments R0 and takes 2 steps
      -- After 5 steps: Step 0->1->0->1->0 = 2.5 iterations, so R0 should be 2 or 3
      r0 finalDevice `shouldSatisfy` (>= 2)  -- Should have incremented at least twice
      isHalted finalDevice `shouldBe` False  -- Should not halt in 5 steps

-- | Helper function to run a program for a limited number of steps
runProgramLimited :: Device -> Int -> Device
runProgramLimited device 0 = device
runProgramLimited device steps
  | isHalted device = device
  | otherwise = runProgramLimited (runStep device) (steps - 1)