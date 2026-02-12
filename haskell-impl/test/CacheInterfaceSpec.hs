{-# LANGUAGE RankNTypes #-}
module CacheInterfaceSpec (spec, cacheInterfaceTests, analyzeTestProgram) where

import Test.Hspec
import WildcardCache.Types
import WildcardPattern
import TrackedProcessor
import Data.Maybe (isJust, isNothing)
import Control.Monad (forM_)

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

-- | Generic test suite that validates ANY cache implementation against the WildcardPatternCache interface
cacheInterfaceTests :: forall cache. (WildcardPatternCache cache, Show cache) 
                    => String -> cache -> Spec
cacheInterfaceTests implName emptyCache = describe ("Cache Interface: " ++ implName) $ do
  
  context "Basic Operations" $ do
    it "starts with empty cache" $ do
      let stats = getCacheStats emptyCache
      totalPatterns stats `shouldBe` 0
      cacheHits stats `shouldBe` 0
    
    it "can insert and lookup patterns" $ do
      let program1 = [8, 1]  -- PRINT 1
          analysis1 = analyzeTestProgram program1  
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
          -- Same program should be found
          result = lookupPattern program1 cache1
      
      result `shouldSatisfy` isJust
      fmap originalProgram result `shouldBe` Just program1
    
    it "returns Nothing for unknown patterns" $ do
      let program1 = [8, 1]  -- PRINT 1
          analysis1 = analyzeTestProgram program1  
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
          unknownProgram = [0]  -- Just HALT - completely different
          result = lookupPattern unknownProgram cache1
      
      result `shouldSatisfy` isNothing

  context "Pattern Equivalence - The Core Bug" $ do
    it "recognizes [8,1] and [8,2] as equivalent patterns" $ do
      let program1 = [8, 1]  -- PRINT 1
          program2 = [8, 2]  -- PRINT 2
          analysis1 = analyzeTestProgram program1  
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
          -- program2 should match the cached pattern from program1
          result = lookupPattern program2 cache1
      
      result `shouldSatisfy` isJust
      -- Should return the cached optimization for program1
      fmap originalProgram result `shouldBe` Just program1
    
    it "recognizes all single-digit PRINT instructions as equivalent" $ do
      let singleCharPrograms = [[8,0], [8,1], [8,5], [8,9]]  -- All single-char outputs
          firstProgram = head singleCharPrograms
          analysis1 = analyzeTestProgram firstProgram
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
      -- All other single-char programs should match the first pattern
      forM_ (tail singleCharPrograms) $ \prog -> do
        let result = lookupPattern prog cache1
        result `shouldSatisfy` isJust
        fmap originalProgram result `shouldBe` Just firstProgram
    
    it "distinguishes different output lengths" $ do
      let singleChar = [8, 5]   -- 1 character output  
          doubleChar = [8, 15]  -- 2 character output
          analysis1 = analyzeTestProgram singleChar
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
      -- Different output length should NOT match
      lookupPattern doubleChar cache1 `shouldSatisfy` isNothing
    
    it "handles multiple pattern groups correctly" $ do
      let singleCharProg = [8, 1]   -- 1 character output
          doubleCharProg = [8, 10]  -- 2 character output
          analysis1 = analyzeTestProgram singleCharProg
          analysis2 = analyzeTestProgram doubleCharProg
          optProg1 = optimizeProgram analysis1
          optProg2 = optimizeProgram analysis2
          
          -- Insert both patterns
          cache1 = insertPattern optProg1 emptyCache
          cache2 = insertPattern optProg2 cache1
          
      -- Test equivalence within each group
      lookupPattern [8, 5] cache2 `shouldSatisfy` isJust  -- Should match single-char pattern
      lookupPattern [8, 15] cache2 `shouldSatisfy` isJust -- Should match double-char pattern
      
      -- Test distinction between groups  
      let singleResult = lookupPattern [8, 5] cache2
          doubleResult = lookupPattern [8, 15] cache2
      fmap originalProgram singleResult `shouldBe` Just singleCharProg
      fmap originalProgram doubleResult `shouldBe` Just doubleCharProg

  context "Cache Statistics" $ do
    it "updates pattern count correctly" $ do
      let program1 = [8, 1]
          program2 = [8, 10]  -- Different output length, so different pattern
          analysis1 = analyzeTestProgram program1
          analysis2 = analyzeTestProgram program2
          optProg1 = optimizeProgram analysis1
          optProg2 = optimizeProgram analysis2
          
          cache1 = insertPattern optProg1 emptyCache
          cache2 = insertPattern optProg2 cache1
          
          stats1 = getCacheStats cache1
          stats2 = getCacheStats cache2
      
      totalPatterns stats1 `shouldBe` 1
      totalPatterns stats2 `shouldBe` 2
    
    it "handles equivalent pattern insertions" $ do
      let program1 = [8, 1]  -- PRINT 1
          program2 = [8, 2]  -- PRINT 2 - should be equivalent
          analysis1 = analyzeTestProgram program1
          analysis2 = analyzeTestProgram program2  
          optProg1 = optimizeProgram analysis1
          optProg2 = optimizeProgram analysis2
          
          cache1 = insertPattern optProg1 emptyCache
          cache2 = insertPattern optProg2 cache1  -- This might or might not add a new pattern
          
          stats1 = getCacheStats cache1
          stats2 = getCacheStats cache2
      
      totalPatterns stats1 `shouldBe` 1
      -- The behavior here depends on implementation:
      -- - Smart caches might detect equivalence and not add duplicate
      -- - Simple caches might add it anyway
      -- Both are acceptable as long as lookup works
      totalPatterns stats2 `shouldSatisfy` (\n -> n >= 1 && n <= 2)

  context "Complex Patterns" $ do
    it "handles longer programs with mixed instructions" $ do
      let program1 = [8, 5, 3, 4, 0]  -- PRINT 5, INC R0, INC R1, HALT
          program2 = [8, 7, 3, 4, 0]  -- PRINT 7, INC R0, INC R1, HALT (same single-char output)
          analysis1 = analyzeTestProgram program1
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
          result = lookupPattern program2 cache1
      
      result `shouldSatisfy` isJust
      fmap originalProgram result `shouldBe` Just program1
    
    it "handles programs with unused memory" $ do
      let program1 = [8, 1, 0]  -- PRINT 1, HALT (position 2 unused)
          program2 = [8, 2, 0]  -- PRINT 2, HALT (same pattern)
          analysis1 = analyzeTestProgram program1
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
          result = lookupPattern program2 cache1
      
      result `shouldSatisfy` isJust

  context "Edge Cases" $ do  
    it "handles empty programs" $ do
      let emptyProgram = []
          result = lookupPattern emptyProgram emptyCache
      result `shouldSatisfy` isNothing
    
    it "handles single instruction programs" $ do
      let program1 = [0]  -- Just HALT
          program2 = [7]  -- Just NOP
          analysis1 = analyzeTestProgram program1
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 emptyCache
          
          result = lookupPattern program2 cache1
      
      -- These should NOT match as they're different instructions
      result `shouldSatisfy` isNothing
    
    it "handles maximum length programs" $ do
      let maxProgram = replicate 16 8  -- 16 PRINT instructions
          analysis = analyzeTestProgram maxProgram
          optProg = optimizeProgram analysis
          cache1 = insertPattern optProg emptyCache
          
          result = lookupPattern maxProgram cache1
      
      result `shouldSatisfy` isJust

-- | Main spec function (placeholder for hspec-discover)
spec :: Spec  
spec = describe "CacheInterfaceSpec" $ do
  it "is a helper module for testing cache implementations" $ do
    -- This module provides cacheInterfaceTests function for other test modules
    True `shouldBe` True
