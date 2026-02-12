module TrieCacheSpec (spec) where

import Test.Hspec
import CacheInterfaceSpec (cacheInterfaceTests, analyzeTestProgram)
import WildcardCache.Types
import WildcardCache.Trie
import WildcardPattern
import TrackedProcessor
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Maybe (isJust, isNothing)

-- Default configuration for testing
testConfig :: CacheConfig
testConfig = CacheConfig
    { maxPatterns = Nothing
    , enableStats = True
    , persistenceFile = Nothing
    }

spec :: Spec
spec = describe "TrieCache" $ do
  
  -- Run ALL generic interface tests on the trie cache
  cacheInterfaceTests "TrieCache" (emptyTrieCache testConfig)
  
  -- Add trie-specific behavioral tests (no internal structure access)
  context "Trie Implementation Behavior" $ do
    it "successfully inserts and retrieves simple patterns" $ do
      let program = [8, 1]  -- PRINT 1
          analysis = analyzeTestProgram program
          optProg = optimizeProgram analysis
          cache = insertPattern optProg (emptyTrieCache testConfig)
          
          result = lookupPattern program cache
          
      result `shouldSatisfy` isJust
    
    it "handles fixed byte patterns correctly" $ do
      let program = [0]  -- HALT (fixed instruction)
          analysis = analyzeTestProgram program
          optProg = optimizeProgram analysis
          cache = insertPattern optProg (emptyTrieCache testConfig)
          
          result = lookupPattern program cache
          
      result `shouldSatisfy` isJust
    
    it "handles complex patterns with wildcards" $ do
      let program = [8, 1, 0]  -- PRINT 1, HALT (longer program with unused positions)
          analysis = analyzeTestProgram program
          optProg = optimizeProgram analysis
          cache = insertPattern optProg (emptyTrieCache testConfig)
          
          result = lookupPattern program cache
          
      result `shouldSatisfy` isJust
    
    it "creates AnyOf edges for equivalent instructions" $ do
      let program = [8, 1, 3, 4, 0]  -- PRINT 1, INC R0, INC R1, HALT (has dead code)
          analysis = analyzeTestProgram program
          optProg = optimizeProgram analysis
          cache = insertPattern optProg (emptyTrieCache testConfig)
          
          -- The pattern should contain AnyOf instructions for dead register operations
          pattern = wildcardPattern optProg
          hasAnyOf = any isAnyOfInstruction pattern
          
          isAnyOfInstruction (AnyOf _) = True
          isAnyOfInstruction _ = False
          
      hasAnyOf `shouldBe` True
    
    it "handles pattern insertion order independence" $ do
      let program1 = [8, 1]  -- PRINT 1
          program2 = [8, 2]  -- PRINT 2 (should be equivalent)
          analysis1 = analyzeTestProgram program1
          analysis2 = analyzeTestProgram program2
          optProg1 = optimizeProgram analysis1
          optProg2 = optimizeProgram analysis2
          
          -- Insert in different orders
          cache1 = insertPattern optProg2 $ insertPattern optProg1 (emptyTrieCache testConfig)
          cache2 = insertPattern optProg1 $ insertPattern optProg2 (emptyTrieCache testConfig)
          
          -- Both should be able to find both programs
          result1a = lookupPattern program1 cache1
          result1b = lookupPattern program2 cache1
          result2a = lookupPattern program1 cache2
          result2b = lookupPattern program2 cache2
          
      result1a `shouldSatisfy` isJust
      result1b `shouldSatisfy` isJust
      result2a `shouldSatisfy` isJust
      result2b `shouldSatisfy` isJust
    
    it "pattern matching traverses trie correctly" $ do
      let program1 = [8, 5, 0]  -- PRINT 5, HALT
          program2 = [8, 7, 0]  -- PRINT 7, HALT (same single-char output pattern)
          analysis1 = analyzeTestProgram program1
          optProg1 = optimizeProgram analysis1
          cache1 = insertPattern optProg1 (emptyTrieCache testConfig)
          
          -- Manually trace the pattern matching
          result = lookupPattern program2 cache1
          
      result `shouldSatisfy` isJust
      -- Should return the cached result for program1
      fmap originalProgram result `shouldBe` Just program1

  context "Trie Pattern Storage Behavior" $ do
    it "stores and retrieves patterns correctly" $ do
      let program = [8, 1]
          analysis = analyzeTestProgram program
          optProg = optimizeProgram analysis
          cache = insertPattern optProg (emptyTrieCache testConfig)
          
          result = lookupPattern program cache
          
      result `shouldSatisfy` isJust
      let stats = getCacheStats cache
      totalPatterns stats `shouldBe` 1
    
    it "handles multiple different patterns correctly" $ do
      let program1 = [8, 1]
          program2 = [8, 10]  -- Different output length, so different pattern
          analysis1 = analyzeTestProgram program1
          analysis2 = analyzeTestProgram program2
          optProg1 = optimizeProgram analysis1
          optProg2 = optimizeProgram analysis2
          
          cache1 = insertPattern optProg1 (emptyTrieCache testConfig)
          cache2 = insertPattern optProg2 cache1
          
          stats1 = getCacheStats cache1
          stats2 = getCacheStats cache2
          
      totalPatterns stats1 `shouldBe` 1
      totalPatterns stats2 `shouldBe` 2
      
      -- Both programs should be retrievable
      lookupPattern program1 cache2 `shouldSatisfy` isJust
      lookupPattern program2 cache2 `shouldSatisfy` isJust

  context "Trie Edge Cases" $ do
    it "handles identical patterns correctly" $ do
      let program1 = [8, 1]
          program2 = [8, 1]  -- Exactly the same program
          analysis1 = analyzeTestProgram program1
          analysis2 = analyzeTestProgram program2
          optProg1 = optimizeProgram analysis1
          optProg2 = optimizeProgram analysis2
          
          cache1 = insertPattern optProg1 (emptyTrieCache testConfig)
          cache2 = insertPattern optProg2 cache1
          
      -- Should be able to look up the program
      lookupPattern program1 cache2 `shouldSatisfy` isJust
      lookupPattern program2 cache2 `shouldSatisfy` isJust
    
    it "handles empty trie lookup gracefully" $ do
      let emptyCache = emptyTrieCache testConfig
          result = lookupPattern [8, 1] emptyCache
          
      result `shouldSatisfy` isNothing
    
    it "handles very long patterns" $ do
      let longProgram = [8, 1] ++ replicate 14 0  -- PRINT 1 followed by 14 HALTs
          analysis = analyzeTestProgram longProgram
          optProg = optimizeProgram analysis
          cache1 = insertPattern optProg (emptyTrieCache testConfig)
          
          result = lookupPattern longProgram cache1
          
      result `shouldSatisfy` isJust

  context "Trie Performance Characteristics" $ do
    it "maintains reasonable memory usage" $ do
      let programs = [[8, n] | n <- [0..15]]  -- All possible single PRINT programs
          analyses = map analyzeTestProgram programs
          optProgs = map optimizeProgram analyses
          
          finalCache = foldl (flip insertPattern) (emptyTrieCache testConfig) optProgs
          stats = getCacheStats finalCache
          
      -- Should have some patterns (might be grouped by equivalence)
      totalPatterns stats `shouldSatisfy` (> 0)
      totalPatterns stats `shouldSatisfy` (<= 16)  -- At most 16 unique patterns
    
    it "lookup performance is reasonable" $ do
      let testProgram = [8, 5, 0]
          analysis = analyzeTestProgram testProgram
          optProg = optimizeProgram analysis
          cache1 = insertPattern optProg (emptyTrieCache testConfig)
          
          -- Lookup should complete without hanging
          result = lookupPattern testProgram cache1
          
      result `shouldSatisfy` isJust