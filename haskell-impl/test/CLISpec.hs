module CLISpec (spec) where

import CLI (parseCommandArgs)
import Data.List (isInfixOf)
import Test.Hspec

spec :: Spec
spec = describe "CLI argument parsing" $ do
    it "uses the documented default limits for run and trace" $ do
        case parseCommandArgs ["run", "--program", "8,15,0"] of
            Right command -> show command `shouldSatisfy` isInfixOf "programMaxSteps = 1000"
            Left message -> expectationFailure message
        case parseCommandArgs ["trace", "--program", "8,15,0"] of
            Right command -> show command `shouldSatisfy` isInfixOf "programMaxSteps = 10000"
            Left message -> expectationFailure message

    it "accepts an explicit step maximum" $
        parseCommandArgs ["run", "--program", "0", "--max-steps", "12"]
            `shouldSatisfy` (either (const False) (isInfixOf "programMaxSteps = 12" . show))

    it "reports missing required program input" $
        parseCommandArgs ["run"] `shouldSatisfy` (either (isInfixOf "--program") (const False))

    it "renders help text for the run command" $
        parseCommandArgs ["run", "--help"] `shouldSatisfy`
            (either (\message -> "Usage:" `isInfixOf` message && "--max-steps" `isInfixOf` message) (const False))

    it "rejects unknown commands with usage guidance" $
        parseCommandArgs ["not-a-command"] `shouldSatisfy`
            (either (\message -> "Usage:" `isInfixOf` message) (const False))

    it "keeps help available for every existing subcommand" $
        mapM_ (\name -> parseCommandArgs [name, "--help"] `shouldSatisfy`
                    (either (\message -> "Usage:" `isInfixOf` message) (const False)))
            ["demo", "optimize-demo", "cache-demo", "search", "solve", "run", "trace"]
