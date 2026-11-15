module PatternCachePropertySpec (spec) where

import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy as Lazy
import qualified Data.ByteString.Lazy.Char8 as LazyChar8
import qualified Data.Map.Strict as Map
import Data.Time (getCurrentTime)
import ExecutionTracing
import PatternCache
import ProcessorTestSupport (genProgram, shrinkProgram)
import System.Directory (removeFile)
import System.IO (hClose, hPutStr)
import System.IO.Temp (withSystemTempFile)
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck

spec :: Spec
spec = describe "PatternCache properties and failure handling" $ do
    modifyMaxSuccess (max 300) $
        prop "round-trips generated cache entries through JSON" $
            forAllShrink genProgram shrinkProgram $ \program -> ioProperty $ do
                now <- getCurrentTime
                cache <- emptyCache ""
                let result = ProgramResult
                        { resultOutput = length program
                        , resultSteps = length program
                        , resultTermination = Halt
                        , resultTrace = ExecutionTrace [] 0 (ExecutionState 0 0 0 0 0 Nothing)
                        , resultProgram = program
                        , resultTimestamp = now
                        }
                populated <- addPatternEntry program result cache
                let encoded = encode populated
                    decoded = eitherDecode encoded :: Either String ProgramCache
                pure $ case decoded of
                    Left message -> counterexample message False
                    Right restored -> counterexample ("encoded cache: " ++ show (Lazy.unpack encoded))
                        (restored == populated && encode restored == encoded)

    it "returns the stored result and increments hit counters" $ do
        now <- getCurrentTime
        cache <- emptyCache ""
        let program = [8, 15, 0]
            result = ProgramResult 2 2 Halt
                (ExecutionTrace [] 0 (ExecutionState 0 0 0 0 0 Nothing)) program now
        populated <- addPatternEntry program result cache
        (found, updated) <- lookupPattern program populated
        found `shouldBe` Just (PatternResult 2 2 Halt 1.0)
        cacheHits (cacheStatistics updated) `shouldBe` 1
        cacheMisses (cacheStatistics updated) `shouldBe` 0
        entryMatchCount (cachePatterns updated Map.! show program) `shouldBe` 2

    it "falls back to an empty cache when the cache file is malformed" $
        withSystemTempFile "malformed-cache.json" $ \path handle -> do
            hPutStr handle "{not valid json"
            hClose handle
            cache <- loadCache path
            cacheFilePath cache `shouldBe` path
            Map.null (cachePatterns cache) `shouldBe` True
            cacheVersion cache `shouldBe` "1.0"

    it "creates an empty cache when the cache file is missing" $
        withSystemTempFile "missing-cache.json" $ \path handle -> do
            hClose handle
            removeFile path
            cache <- loadCache path
            cacheFilePath cache `shouldBe` path
            Map.null (cachePatterns cache) `shouldBe` True

    it "rejects malformed JSON instead of decoding a partial cache" $
        (eitherDecode (LazyChar8.pack "not-json") :: Either String ProgramCache) `shouldSatisfy` isLeft

    it "loads cache records written before optional statistics were added" $ do
        let oldFormat = LazyChar8.pack
                "{\"cache_version\":\"0.1\",\"statistics\":{\"total_patterns\":0,\"cache_hits\":0,\"cache_misses\":0,\"last_updated\":\"2020-01-01T00:00:00Z\"},\"patterns\":[]}"
            decoded = eitherDecode oldFormat :: Either String ProgramCache
        decoded `shouldSatisfy` isRight
        case decoded of
            Left _ -> expectationFailure "old cache format failed to decode"
            Right cache -> do
                cacheVersion cache `shouldBe` "0.1"
                executionsSaved (cacheStatistics cache) `shouldBe` 0
                wildcardHits (cacheStatistics cache) `shouldBe` 0
                similarityHits (cacheStatistics cache) `shouldBe` 0
                totalExecutions (cacheStatistics cache) `shouldBe` 0
  where
    isLeft (Left _) = True
    isLeft _ = False
    isRight (Right _) = True
    isRight _ = False
