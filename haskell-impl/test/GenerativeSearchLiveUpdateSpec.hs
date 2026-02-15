module GenerativeSearchLiveUpdateSpec (spec) where

import Test.Hspec
import Data.Word (Word8)
import GenerativeTrie
import GenerativeSearch
import TrackedProcessor (createTrackedDevice, runTrackedProgramLoopCheck)
import WildcardPattern (analyzeProgram, optimizeProgram, OptimizedProgram)

-- Helper to create a dummy OptimizedProgram from a program
makeDummyOptimized :: [Word8] -> OptimizedProgram
makeDummyOptimized prog =
    case createTrackedDevice prog of
        Left _ -> error "Failed to create device"
        Right device ->
            let finalDevice = runTrackedProgramLoopCheck device
                analysis = analyzeProgram prog finalDevice
            in optimizeProgram analysis

spec :: Spec
spec = describe "GenerativeSearch Live Pattern Updates" $ do
    
    describe "Sequential pattern accumulation" $ do
        it "correctly excludes first found program in subsequent searches" $ do
            let trie0 = emptyTrie
                -- First search finds program [0,0,0]
                prog1 = [0, 0, 0]
                opt1 = makeDummyOptimized prog1
                trie1 = insertPattern opt1 trie0
                
                -- Generate candidates with updated trie
                candidates1 = generateCandidates 3 trie1
            
            -- First program should be excluded
            candidates1 `shouldSatisfy` notElem prog1
            
        it "correctly accumulates multiple patterns over 5 iterations" $ do
            let -- Iteration 1: Add first pattern
                trie0 = emptyTrie
                prog1 = [0, 0, 1]
                opt1 = makeDummyOptimized prog1
                trie1 = insertPattern opt1 trie0
                
                -- Iteration 2: Add second pattern
                prog2 = [1, 0, 0]
                opt2 = makeDummyOptimized prog2
                trie2 = insertPattern opt2 trie1
                
                -- Iteration 3: Add third pattern
                prog3 = [2, 0, 0]
                opt3 = makeDummyOptimized prog3
                trie3 = insertPattern opt3 trie2
                
                -- Iteration 4: Add fourth pattern
                prog4 = [3, 0, 0]
                opt4 = makeDummyOptimized prog4
                trie4 = insertPattern opt4 trie3
                
                -- Iteration 5: Add fifth pattern
                prog5 = [4, 0, 0]
                opt5 = makeDummyOptimized prog5
                trie5 = insertPattern opt5 trie4
                
                -- Final generation with all 5 patterns excluded
                finalCandidates = generateCandidates 3 trie5
            
            -- All 5 programs should be excluded
            finalCandidates `shouldSatisfy` notElem prog1
            finalCandidates `shouldSatisfy` notElem prog2
            finalCandidates `shouldSatisfy` notElem prog3
            finalCandidates `shouldSatisfy` notElem prog4
            finalCandidates `shouldSatisfy` notElem prog5
            
            -- Total candidates should be reduced by 5
            length finalCandidates `shouldBe` (4096 - 5)
            
        it "maintains candidate count invariant: total excluded = accumulated patterns" $ do
            let patterns = [ [0, 1, 2], [1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6] ]
                trie0 = emptyTrie
                
                -- Build up trie with each pattern
                trie1 = insertPattern (makeDummyOptimized (patterns !! 0)) trie0
                trie2 = insertPattern (makeDummyOptimized (patterns !! 1)) trie1
                trie3 = insertPattern (makeDummyOptimized (patterns !! 2)) trie2
                trie4 = insertPattern (makeDummyOptimized (patterns !! 3)) trie3
                trie5 = insertPattern (makeDummyOptimized (patterns !! 4)) trie4
                
                candidates0 = generateCandidates 3 trie0
                candidates5 = generateCandidates 3 trie5
                
                excluded = length candidates0 - length candidates5
            
            -- Should exclude at least the patterns we added
            excluded `shouldBe` 5
            
        it "search results are monotonically decreasing in candidate count" $ do
            let progs = [ [0, 0, 0], [1, 1, 1], [2, 2, 2], [3, 3, 3], [4, 4, 4] ]
                tryies = scanl (\t p -> insertPattern (makeDummyOptimized p) t) emptyTrie progs
                candidateCounts = map (\t -> length $ generateCandidates 3 t) tryies
            
            -- Candidate counts should monotonically decrease
            candidateCounts `shouldBe` [4096, 4095, 4094, 4093, 4092, 4091]
