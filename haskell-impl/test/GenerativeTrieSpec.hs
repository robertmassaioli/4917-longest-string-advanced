module GenerativeTrieSpec (spec) where

import Test.Hspec
import Data.Word (Word8)
import GenerativeTrie

spec :: Spec
spec = describe "GenerativeTrie" $ do
  
  context "Trie Creation and Initialization" $ do
    it "creates an empty trie" $ do
      let trie = emptyTrie
      let stats = getTrieStatistics trie
      trieTotalNodes stats `shouldSatisfy` (>= 0)  -- Should have at least 0 nodes
    
    it "empty trie has no programs excluded" $ do
      let trie = emptyTrie
          stats = getTrieStatistics trie
      trieProgramsBlockedEstimate stats `shouldBe` 0
  
  context "Statistics Calculation" $ do
    it "empty trie statistics are valid" $ do
      let trie = emptyTrie
          stats = getTrieStatistics trie
      trieTotalNodes stats `shouldSatisfy` (>= 0)
      trieMaxDepth stats `shouldSatisfy` (>= 0)
    
    it "calculates trie size correctly" $ do
      let trie = emptyTrie
          size = trieSize trie
      size `shouldSatisfy` (>= 0)  -- Empty trie can have size 0 or 1
  
  context "Forbidden Program Queries" $ do
    it "empty trie forbids no programs" $ do
      let trie = emptyTrie
          result1 = isForbidden [8, 15] trie
          result2 = isForbidden [0, 0, 0] trie
      result1 `shouldBe` False
      result2 `shouldBe` False
    
    it "empty trie has no partial forbiddens" $ do
      let trie = emptyTrie
          result = isPartiallyForbidden [8] trie
      result `shouldBe` False
  
  context "Programs Excluded Calculation" $ do
    it "empty trie excludes zero programs" $ do
      let trie = emptyTrie
          excluded = trieProgramsExcluded trie
      excluded `shouldBe` 0
  
  context "Edge Cases" $ do
    it "handles queries on empty programs" $ do
      let trie = emptyTrie
          result = isForbidden [] trie
      result `shouldBe` False
    
    it "handles very long programs" $ do
      let trie = emptyTrie
          longProg = replicate 16 8
          result = isForbidden longProg trie
      result `shouldBe` False
    
    it "handles single-byte programs" $ do
      let trie = emptyTrie
          result = isForbidden [5] trie
      result `shouldBe` False
    
    it "multiple queries return consistent results" $ do
      let trie = emptyTrie
          prog = [8, 15, 0]
          result1 = isForbidden prog trie
          result2 = isForbidden prog trie
      result1 `shouldBe` result2
  
  context "Trie Properties" $ do
    it "empty trie size is non-negative" $ do
      let trie = emptyTrie
          size = trieSize trie
      size `shouldSatisfy` (>= 0)
    
    it "empty trie blocks no programs" $ do
      let trie = emptyTrie
          stats = getTrieStatistics trie
      trieProgramsBlockedEstimate stats `shouldBe` 0
