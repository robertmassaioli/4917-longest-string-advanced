{-# LANGUAGE ApplicativeDo #-}

module CLI
    ( Command(..)
    , DemoOptions(..)
    , BenchmarkOptions(..)
    , CacheDemoOptions(..)
    , TestOptions(..)
    , SearchOptions(..)
    , SolveOptions(..)
    , parseCommand
    , runCommand
    ) where

import Options.Applicative
import Data.Semigroup ((<>))
import Commands.Demo (runDemoCommand)
import Commands.Benchmark (runBenchmarkCommand)
import Commands.CacheDemo (runCacheDemoCommand)
import Commands.Test (runTestCommand)
import Commands.Search (runSearchCommand)
import Commands.Solve (runSolveCommand)

-- | Available commands
data Command 
    = Demo DemoOptions
    | Benchmark BenchmarkOptions  
    | CacheDemo CacheDemoOptions
    | Test TestOptions
    | Search SearchOptions
    | Solve SolveOptions
    deriving (Show, Eq)

-- | Options for demo command
data DemoOptions = DemoOptions
    { demoLength :: Maybe Int
    , demoVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for benchmark command
data BenchmarkOptions = BenchmarkOptions
    { benchmarkAll :: Bool
    , benchmarkVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for cache demo command
data CacheDemoOptions = CacheDemoOptions
    { cacheDemoLength :: Maybe Int
    , cacheDemoVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for test command
data TestOptions = TestOptions
    { testPattern :: Maybe String
    , testVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for search command
data SearchOptions = SearchOptions
    { searchLength :: Int
    , searchCached :: Bool
    , searchVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for solve command
data SolveOptions = SolveOptions
    { solveTaskFile :: Maybe String
    , solveVerbose :: Bool
    } deriving (Show, Eq)

-- | Parse command line arguments
parseCommand :: IO Command
parseCommand = execParser $ info (commandParser <**> helper)
    ( fullDesc
   <> progDesc "4917 Processor - Longest String Problem Solver"
   <> header "haskell-impl - A comprehensive toolkit for the 4917 processor" )

-- | Main command parser
commandParser :: Parser Command
commandParser = hsubparser
    ( command "demo"       (info demoParser       (progDesc "Run processor demonstration"))
   <> command "benchmark"  (info benchmarkParser  (progDesc "Run performance benchmarks"))
   <> command "cache-demo" (info cacheDemoParser  (progDesc "Demonstrate persistent memoization"))
   <> command "test"       (info testParser       (progDesc "Run processor tests"))
   <> command "search"     (info searchParser     (progDesc "Search for optimal programs"))
   <> command "solve"      (info solveParser      (progDesc "Solve specific tasks"))
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

-- | Parser for benchmark command
benchmarkParser :: Parser Command
benchmarkParser = do
    all_ <- switch
        ( long "all"
       <> short 'a'
       <> help "Run all benchmarks including slower ones" )
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    pure $ Benchmark $ BenchmarkOptions all_ verbose

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
    pure $ CacheDemo $ CacheDemoOptions length_ verbose

-- | Parser for test command
testParser :: Parser Command
testParser = do
    pattern_ <- optional $ strOption
        ( long "pattern"
       <> short 'p'
       <> metavar "PATTERN"
       <> help "Run tests matching pattern" )
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    pure $ Test $ TestOptions pattern_ verbose

-- | Parser for search command
searchParser :: Parser Command
searchParser = do
    length_ <- option auto
        ( long "length"
       <> short 'l'
       <> metavar "N"
       <> help "Program length to search"
       <> showDefault
       <> value 3 )
    cached <- switch
        ( long "cached"
       <> short 'c'
       <> help "Use persistent memoization cache" )
    verbose <- switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    pure $ Search $ SearchOptions length_ cached verbose

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

-- | Execute a command
runCommand :: Command -> IO ()
runCommand (Demo opts) = runDemoCommand (demoLength opts) (demoVerbose opts)
runCommand (Benchmark opts) = runBenchmarkCommand (benchmarkAll opts) (benchmarkVerbose opts)
runCommand (CacheDemo opts) = runCacheDemoCommand (cacheDemoLength opts) (cacheDemoVerbose opts)
runCommand (Test opts) = runTestCommand (testPattern opts) (testVerbose opts)
runCommand (Search opts) = runSearchCommand (searchLength opts) (searchCached opts) (searchVerbose opts)
runCommand (Solve opts) = runSolveCommand (solveTaskFile opts) (solveVerbose opts)