{-# LANGUAGE ApplicativeDo #-}

module CLI
    ( Command(..)
    , DemoOptions(..)
    , OptimizeDemoOptions(..)
    , CacheDemoOptions(..)
    , SearchOptions(..)
    , SolveOptions(..)
    , parseCommand
    , parseCommandArgs
    , runCommand
    ) where

import Options.Applicative
import Commands.Demo (runDemoCommand)
import Commands.OptimizeDemo (runOptimizeDemoCommand)
import Commands.CacheDemo (runCacheDemoCommand)
import Commands.Search (runSearchCommand)
import Commands.Solve (runSolveCommand)
import Commands.ProgramExecution (runProgramCommand, runTraceCommand)
import Commands.Generalize (runGeneralizeCommand)

-- | Available commands
data Command 
    = Demo DemoOptions
    | OptimizeDemo OptimizeDemoOptions
    | CacheDemo CacheDemoOptions
    | Search SearchOptions
    | Solve SolveOptions
    | Run ProgramOptions
    | Trace ProgramOptions
    | Generalize GeneralizeOptions
    deriving (Show, Eq)

-- | Options for demo command
data DemoOptions = DemoOptions
    { demoLength :: Maybe Int
    , demoVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for optimization demo command
data OptimizeDemoOptions = OptimizeDemoOptions
    { optimizeDemoVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for cache demo command
data CacheDemoOptions = CacheDemoOptions
    { cacheDemoLength :: Maybe Int
    , cacheDemoVerbose :: Bool
    , cacheDemoFresh :: Bool
    , cacheDemoCacheFile :: String
    } deriving (Show, Eq)


-- | Options for search command
data SearchOptions = SearchOptions
    { searchLength :: Int
    , searchFresh :: Bool
    , searchCacheFile :: String
    , searchVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for solve command
data SolveOptions = SolveOptions
    { solveTaskFile :: Maybe String
    , solveVerbose :: Bool
    } deriving (Show, Eq)

data ProgramOptions = ProgramOptions
    { suppliedProgram :: String
    , programMaxSteps :: Int
    , programDetectLoops :: Bool
    } deriving (Show, Eq)

data GeneralizeOptions = GeneralizeOptions
    { generalizeProgram :: String
    } deriving (Show, Eq)

-- | Parse command line arguments
parseCommand :: IO Command
parseCommand = execParser commandInfo

-- | Pure command-line parsing for deterministic tests and embedding callers.
parseCommandArgs :: [String] -> Either String Command
parseCommandArgs arguments = case execParserPure defaultPrefs commandInfo arguments of
    Success parsedCommand -> Right parsedCommand
    Failure failure -> Left (fst (renderFailure failure "4917-cli"))
    CompletionInvoked _ -> Left "command completion was requested"

commandInfo :: ParserInfo Command
commandInfo = info (commandParser <**> helper)
    ( fullDesc
   <> progDesc "4917 Processor - Longest String Problem Solver"
   <> header "4917-cli - A comprehensive toolkit for the 4917 processor" )

-- | Main command parser
commandParser :: Parser Command
commandParser = hsubparser
    ( command "demo"           (info demoParser           (progDesc "Run processor demonstration"))
   <> command "optimize-demo"  (info optimizeDemoParser  (progDesc "Demonstrate program optimization"))
   <> command "cache-demo"     (info cacheDemoParser     (progDesc "Demonstrate persistent memoization"))
   <> command "search"         (info searchParser        (progDesc "Search for optimal programs"))
   <> command "solve"          (info solveParser         (progDesc "Solve specific tasks"))
   <> command "run"            (info runParser            (progDesc "Execute a supplied program"))
   <> command "trace"          (info traceParser          (progDesc "Trace a supplied program step by step"))
   <> command "generalize"     (info generalizeParser     (progDesc "Trace memory usage and emit a generalized program pattern"))
   )

-- | Parser for demo command
demoParser :: Parser Command
demoParser = do
    length_ <- optional $ option auto
        ( long "length"
       <> short 'l'
       <> metavar "N"
       <> help "Specific program length to demonstrate (default: run lengths 1-6)" )
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    pure $ Demo $ DemoOptions length_ verbose

-- | Parser for optimization demo command
optimizeDemoParser :: Parser Command
optimizeDemoParser = do
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output with full optimization details" )
    pure $ OptimizeDemo $ OptimizeDemoOptions verbose


-- | Parser for cache demo command
cacheDemoParser :: Parser Command
cacheDemoParser = do
    length_ <- optional $ option auto
        ( long "length"
       <> short 'l'
       <> metavar "N"
       <> help "Program length to test (default: 3)" )
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    fresh <- switch
        ( long "fresh"
       <> short 'f'
       <> help "Delete existing cache file before running (start fresh)" )
    cacheFile <- strOption
        ( long "cache-file"
       <> short 'c'
       <> metavar "FILE"
       <> help "Cache file path (default: program_cache.json)"
       <> showDefault
       <> value "program_cache.json" )
    pure $ CacheDemo $ CacheDemoOptions length_ verbose fresh cacheFile


-- | Parser for search command
searchParser :: Parser Command
searchParser = Search <$> (SearchOptions
    <$> option auto
        ( long "length"
       <> short 'l'
       <> metavar "N"
       <> help "Program length to search"
       <> showDefault
       <> value 3 )
    <*> switch
        ( long "fresh"
       <> short 'f'
       <> help "Delete existing cache file before running (start fresh)" )
    <*> strOption
        ( long "cache-file"
       <> short 'c'
       <> metavar "FILE"
       <> help "Cache file path (default: search_cache.json)"
       <> showDefault
       <> value "search_cache.json" )
    <*> switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" ))

-- | Parser for solve command
solveParser :: Parser Command
solveParser = do
    taskFile <- optional $ strOption
        ( long "task-file"
       <> short 'f'
       <> metavar "FILE"
       <> help "Task file to solve" )
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    pure $ Solve $ SolveOptions taskFile verbose

runParser :: Parser Command
runParser = Run <$> programOptions 1000

traceParser :: Parser Command
traceParser = do
    options <- programOptions 10000
    detectLoops <- switch
        ( long "detect-loops"
       <> help "Trace until HALT or a repeated machine state; ignore --max-steps" )
    pure $ Trace options { programDetectLoops = detectLoops }

generalizeParser :: Parser Command
generalizeParser = Generalize <$> (GeneralizeOptions <$> strOption
    ( long "program"
   <> metavar "BYTE,BYTE,..."
   <> help "Comma-separated memory bytes (integers 0-15, up to 16 values)" ))

programOptions :: Int -> Parser ProgramOptions
programOptions defaultMaxSteps = do
    program <- strOption
        ( long "program"
       <> metavar "BYTE,BYTE,..."
       <> help "Comma-separated memory bytes (integers 0-15, up to 16 values)" )
    maxSteps <- option auto
        ( long "max-steps"
       <> metavar "N"
       <> help ("Maximum instructions before stopping (default: " ++ show defaultMaxSteps ++ ")")
       <> value defaultMaxSteps )
    pure $ ProgramOptions program maxSteps False

-- | Execute a command
runCommand :: Command -> IO ()
runCommand (Demo opts) = runDemoCommand (demoLength opts) (demoVerbose opts)
runCommand (OptimizeDemo opts) = runOptimizeDemoCommand (optimizeDemoVerbose opts)
runCommand (CacheDemo opts) = runCacheDemoCommand (cacheDemoLength opts) (cacheDemoVerbose opts) (cacheDemoFresh opts) (cacheDemoCacheFile opts)
runCommand (Search opts) = runSearchCommand (searchLength opts) (searchFresh opts) (searchCacheFile opts) (searchVerbose opts)
runCommand (Solve opts) = runSolveCommand (solveTaskFile opts) (solveVerbose opts)
runCommand (Run opts) = runProgramCommand (suppliedProgram opts) (programMaxSteps opts)
runCommand (Trace opts) = runTraceCommand (suppliedProgram opts) (programMaxSteps opts) (programDetectLoops opts)
runCommand (Generalize opts) = runGeneralizeCommand (generalizeProgram opts)
