module GenerativeSearchPropSpec (spec) where

import Test.Hspec
import Data.Word (Word8)
import GenerativeTrie
import GenerativeSearch
import TrackedProcessor (createTrackedDevice, runTrackedProgramLoopCheck)
import WildcardPattern (analyzeProgram, optimizeProgram, OptimizedProgram)

spec :: Spec
spec = describe "GenerativeSearch Primary Operations" $ do
  
  context "Candidate Generation - Correctness" $ do
    it "generates exactly 16^N candidates for length N with empty trie" $ do
      let trie = emptyTrie
          len = 3
          candidates = generateCandidates len trie
      length candidates `shouldBe` 16 ^ len
    
    it "all generated candidates have correct length" $ do
      let trie = emptyTrie
          len = 3
          candidates = take 100 $ generateCandidates len trie
      all (\prog -> length prog == len) candidates `shouldBe` True
    
    it "all generated candidates contain only valid bytes (0-15)" $ do
      let trie = emptyTrie
          candidates = take 100 $ generateCandidates 3 trie
      all (\prog -> all (<= 15) prog) candidates `shouldBe` True
    
    it "generates candidates in order (lexicographic)" $ do
      let trie = emptyTrie
          candidates = take 20 $ generateCandidates 2 trie
      candidates `shouldBe` 
        [[0,0], [0,1], [0,2], [0,3], [0,4], [0,5], [0,6], [0,7], [0,8], [0,9],
         [0,10], [0,11], [0,12], [0,13], [0,14], [0,15],
         [1,0], [1,1], [1,2], [1,3]]
    
    it "no duplicate candidates are generated" $ do
      let trie = emptyTrie
          candidates = take 256 $ generateCandidates 2 trie
          noDups = length candidates == length (nubOrd candidates)
      noDups `shouldBe` True
  
  context "Trie Filtering - Correctness" $ do
    it "forbidden programs are not generated" $ do
      let forbidden = [8, 10, 8]
          trie = insertPattern (makeDummyOptimized forbidden) emptyTrie
          candidates = generateCandidates 3 trie
      candidates `shouldSatisfy` notElem forbidden
    
    it "similar programs to forbidden patterns are also excluded" $ do
      let pattern = [8, 10, 8]
          trie = insertPattern (makeDummyOptimized pattern) emptyTrie
          candidates = generateCandidates 3 trie
      -- [8, 10, 8] should be forbidden
      candidates `shouldSatisfy` notElem [8, 10, 8]
      -- But [8, 9, 8] might still be there (different operand)
      -- This depends on wildcard patterns
      length candidates `shouldSatisfy` (< 4096)
    
    it "multiple forbidden patterns are respected" $ do
      let forbidden1 = [0, 0, 0]
          forbidden2 = [1, 1, 1]
          forbidden3 = [2, 2, 2]
          trie = insertPattern (makeDummyOptimized forbidden1) $
                  insertPattern (makeDummyOptimized forbidden2) $
                  insertPattern (makeDummyOptimized forbidden3) emptyTrie
          candidates = generateCandidates 3 trie
      candidates `shouldSatisfy` notElem [0, 0, 0]
      candidates `shouldSatisfy` notElem [1, 1, 1]
      candidates `shouldSatisfy` notElem [2, 2, 2]
  
  context "Lazy Evaluation - Behavior" $ do
    it "does not materialize all candidates upfront" $ do
      let trie = emptyTrie
          -- Length 5 = 16^5 = 1,048,576 candidates
          -- If fully materialized, this would take significant memory
          candidates = generateCandidates 5 trie
          first100 = take 100 candidates
      -- Should be able to take first 100 without hanging
      length first100 `shouldBe` 100
    
    it "can generate candidates incrementally" $ do
      let trie = emptyTrie
          candidates = generateCandidates 3 trie
          batch1 = take 1000 candidates
          batch2 = drop 1000 (take 2000 candidates)
      length batch1 `shouldBe` 1000
      length batch2 `shouldBe` 1000
  
  context "Heuristic Generation - Behavior" $ do
    it "generates same number of candidates as basic generation" $ do
      let trie = emptyTrie
          basic = take 200 $ generateCandidates 3 trie
          heuristic = take 200 $ generateCandidatesWithHeuristic 3 trie
      length basic `shouldBe` length heuristic
    
    it "heuristic ordering differs from basic ordering" $ do
      let trie = emptyTrie
          basic = take 50 $ generateCandidates 3 trie
          heuristic = take 50 $ generateCandidatesWithHeuristic 3 trie
      -- They should have different order (though might overlap)
      (basic == heuristic) `shouldBe` False
    
    it "heuristic version respects trie constraints" $ do
      let forbidden = [13, 0, 0]  -- JMP instruction
          trie = insertPattern (makeDummyOptimized forbidden) emptyTrie
          candidates = take 100 $ generateCandidatesWithHeuristic 3 trie
      candidates `shouldSatisfy` notElem [13, 0, 0]

-- Helper to create dummy OptimizedProgram from raw bytes
makeDummyOptimized :: [Word8] -> OptimizedProgram
makeDummyOptimized prog = 
  let padded = prog ++ replicate (16 - length prog) 0
  in case createTrackedDevice padded of
       Left _ -> error "Failed to create device"
       Right device -> 
           let finalDevice = runTrackedProgramLoopCheck device
               analysis = analyzeProgram padded finalDevice
           in optimizeProgram analysis

-- Helper to check for duplicates
nubOrd :: Eq a => [a] -> [a]
nubOrd [] = []
nubOrd (x:xs) = x : nubOrd (filter (/= x) xs)
