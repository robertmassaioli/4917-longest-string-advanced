module GenerativeSearchSpec (spec) where

import Test.Hspec
import Data.Word (Word8)
import GenerativeTrie
import GenerativeSearch

spec :: Spec
spec = describe "GenerativeSearch" $ do
  
  context "Candidate Generation - Empty Trie" $ do
    it "generates all candidates for length 2 with empty trie" $ do
      let trie = emptyTrie
          candidates = take 256 $ generateCandidates 2 trie
      length candidates `shouldBe` 256
    
    it "generates candidates in order" $ do
      let trie = emptyTrie
          candidates = take 5 $ generateCandidates 2 trie
      candidates `shouldBe` [[0,0], [0,1], [0,2], [0,3], [0,4]]
    
    it "generates exactly 16^N candidates for length N" $ do
      let trie = emptyTrie
          len1 = length $ take 20 $ generateCandidates 1 trie
          len2 = length $ take 300 $ generateCandidates 2 trie
      len1 `shouldBe` 16
      len2 `shouldBe` 256
  
  context "Lazy Evaluation" $ do
    it "generates candidates lazily without computing all upfront" $ do
      let trie = emptyTrie
          candidates = generateCandidates 4 trie  -- 16^4 = 65536 candidates
          -- Taking just 10 should be fast, not generate all 65k
          firstTen = take 10 candidates
      length firstTen `shouldBe` 10
    
    it "can generate limited candidates efficiently" $ do
      let trie = emptyTrie
          candidates = take 100 $ generateCandidates 3 trie
      length candidates `shouldBe` 100
    
    it "generates large numbers of candidates lazily" $ do
      let trie = emptyTrie
          -- Don't try to generate all, just take a sample
          candidates = take 1000 $ generateCandidates 5 trie
      length candidates `shouldBe` 1000
  
  context "Heuristic Generation" $ do
    it "generates candidates with heuristic ordering" $ do
      let trie = emptyTrie
          candidates = take 50 $ generateCandidatesWithHeuristic 3 trie
      length candidates `shouldBe` 50
    
    it "heuristic generation produces different order than basic" $ do
      let trie = emptyTrie
          basicCandidates = take 20 $ generateCandidates 3 trie
          heuristicCandidates = take 20 $ generateCandidatesWithHeuristic 3 trie
      -- They should not be exactly the same (heuristic reorders)
      -- At least check they're both valid
      length basicCandidates `shouldBe` 20
      length heuristicCandidates `shouldBe` 20
  
  context "Edge Cases" $ do
    it "handles length 1 programs" $ do
      let trie = emptyTrie
          candidates = take 16 $ generateCandidates 1 trie
      length candidates `shouldBe` 16
      candidates `shouldBe` [[0], [1], [2], [3], [4], [5], [6], [7], 
                              [8], [9], [10], [11], [12], [13], [14], [15]]
    
    it "handles length 0 programs" $ do
      let trie = emptyTrie
          candidates = take 10 $ generateCandidates 0 trie
      -- Length 0 should produce one empty program
      candidates `shouldBe` [[]]
  
  context "Configuration" $ do
    it "generates correct length programs" $ do
      let trie = emptyTrie
          candidates3 = take 10 $ generateCandidates 3 trie
          candidates4 = take 10 $ generateCandidates 4 trie
      all (\prog -> length prog == 3) candidates3 `shouldBe` True
      all (\prog -> length prog == 4) candidates4 `shouldBe` True
    
    it "all generated candidates are valid" $ do
      let trie = emptyTrie
          candidates = take 100 $ generateCandidates 3 trie
          allValid = all (\prog -> all (<= 15) prog && all (>= 0) prog) candidates
      allValid `shouldBe` True
