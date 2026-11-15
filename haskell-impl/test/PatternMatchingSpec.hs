module PatternMatchingSpec (spec) where

import qualified Data.Map.Strict as Map
import ExecutionTracing (TerminationType(..))
import PatternCache (PatternResult(..))
import PatternMatching
import ProcessorTestSupport (genProgram, shrinkProgram)
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

spec :: Spec
spec = describe "PatternMatching properties" $ do
    modifyMaxSuccess (max 300) $
        prop "exact matcher hits only identical generated programs" $
            forAllShrink genProgram shrinkProgram $ \program ->
                let result = PatternResult 3 5 Halt 0.75
                    matcher = SimplePatternMatcher (Map.singleton program result) 0 0
                    (hit, afterHit) = matchPattern matcher program
                    (miss, afterMiss) = matchPattern afterHit (program ++ [0])
                in hit == Just result
                   && lookupCount afterHit == 1
                   && hitCount afterHit == 1
                   && miss == Nothing
                   && lookupCount afterMiss == 2
                   && hitCount afterMiss == 1
