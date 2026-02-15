{-# LANGUAGE ApplicativeDo #-}

module CLI
    ( Command(..)
    , DemoOptions(..)
    , OptimizeDemoOptions(..)
    , CacheDemoOptions(..)
    , SearchOptions(..)
    , OptimizedSearchOptions(..)
    , GenSearchOptions(..)
    , SolveOptions(..)
    , TestProgramOptions(..)
    , parseCommand
    , runCommand
    ) where

import Options.Applicative
import Commands.Demo (runDemoCommand)
import Commands.OptimizeDemo (runOptimizeDemoCommand)
import Commands.CacheDemo (runCacheDemoCommand)
import Commands.Search (runSearchCommand)
import Commands.OptimizedSearch (runOptimizedSearchCommand, OptimizedSearchOptions(..))
import Commands.GenSearch (runGenSearchCommand)
import Commands.Solve (runSolveCommand)
import Commands.TestProgram (runTestProgramCommand)

-- | Available commands
data Command 
    = Demo DemoOptions
    | OptimizeDemo OptimizeDemoOptions
    | CacheDemo CacheDemoOptions
    | Search SearchOptions
    | OptimizedSearch OptimizedSearchOptions
    | GenSearch GenSearchOptions
    | Solve SolveOptions
    | TestProgram TestProgramOptions
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


-- | Options for generative search command
data GenSearchOptions = GenSearchOptions
    { genSearchLength :: Int
    , genSearchUseHeuristics :: Bool
    , genSearchTrieFile :: Maybe String
    , genSearchPatternFiles :: [FilePath]
    , genSearchVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for solve command
data SolveOptions = SolveOptions
    { solveTaskFile :: Maybe String
    , solveVerbose :: Bool
    } deriving (Show, Eq)

-- | Options for test-program command
data TestProgramOptions = TestProgramOptions
    { testProgramBytes :: [Int]
    } deriving (Show, Eq)

-- | Parse command line arguments
parseCommand :: IO Command
parseCommand = execParser $ info (commandParser <**> helper)
    ( fullDesc
   <> progDesc "4917 Processor - Longest String Problem Solver"
   <> header "4917-cli - A comprehensive toolkit for the 4917 processor" )

-- | Main command parser
commandParser :: Parser Command
commandParser = hsubparser
    ( command "demo"             (info demoParser             (progDesc "Run processor demonstration"))
   <> command "optimize-demo"    (info optimizeDemoParser    (progDesc "Demonstrate program optimization"))
   <> command "cache-demo"       (info cacheDemoParser       (progDesc "Demonstrate persistent memoization"))
   <> command "search"           (info searchParser          (progDesc "Search for optimal programs"))
   <> command "optimized-search" (info optimizedSearchParser (progDesc "Optimized search with wildcard pattern caching"))
   <> command "gen-search"       (info genSearchParser       (progDesc "Generative search with inverted trie filtering"))
   <> command "solve"            (info solveParser           (progDesc "Solve specific tasks"))
   <> command "test-program"     (info testProgramParser     (progDesc "Test a specific program"))
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

-- | Parser for optimized search command
optimizedSearchParser :: Parser Command
optimizedSearchParser = OptimizedSearch <$> (OptimizedSearchOptions
    <$> option auto
        ( long "length"
       <> short 'l'
       <> metavar "N"
       <> help "Program length to search"
       <> showDefault
       <> value 3 )
    <*> strOption
        ( long "cache-type"
       <> short 't'
       <> metavar "TYPE"
       <> help "Cache implementation (trie, vector, dfa)"
       <> showDefault
       <> value "trie" )
    <*> optional (option auto
        ( long "max-patterns"
       <> short 'm'
       <> metavar "N"
       <> help "Maximum patterns to cache" ))
    <*> switch
        ( long "verbose"
       <> short 'v'
       <> help "Enable verbose output" )
    <*> optional (strOption
        ( long "cache-file"
       <> short 'c'
       <> metavar "FILE"
       <> help "Cache persistence file" ))
    <*> switch
        ( long "fresh"
       <> short 'f'
       <> help "Start with fresh cache (ignore existing cache file)" ))

-- | Parser for generative search command
genSearchParser :: Parser Command
genSearchParser = GenSearch <$> (GenSearchOptions
    <$> option auto
        ( long "length"
       <> short 'l'
       <> metavar "N"
       <> help "Program length to search"
       <> showDefault
       <> value 3 )
    <*> switch
        ( long "heuristic"
       <> short 'h'
       <> help "Use heuristic-guided generation (favor jumps, loops)" )
    <*> optional (strOption
        ( long "trie-file"
       <> short 't'
       <> metavar "FILE"
       <> help "Trie persistence file for resumable searches" ))
    <*> many (strOption
        ( long "pattern-file"
       <> short 'p'
       <> metavar "FILE"
       <> help "Wildcard pattern file(s) to load into trie" ))
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

-- | Parser for test-program command
testProgramParser :: Parser Command
testProgramParser = do
    bytes <- some $ argument auto
        ( metavar "BYTES..."
       <> help "Program bytes to test (e.g., 8 15 8 for [8, 15, 8])" )
    pure $ TestProgram $ TestProgramOptions bytes

-- | Execute a command
runCommand :: Command -> IO ()
runCommand (Demo opts) = runDemoCommand (demoLength opts) (demoVerbose opts)
runCommand (OptimizeDemo opts) = runOptimizeDemoCommand (optimizeDemoVerbose opts)
runCommand (CacheDemo opts) = runCacheDemoCommand (cacheDemoLength opts) (cacheDemoVerbose opts) (cacheDemoFresh opts) (cacheDemoCacheFile opts)
runCommand (Search opts) = runSearchCommand (searchLength opts) (searchFresh opts) (searchCacheFile opts) (searchVerbose opts)
runCommand (OptimizedSearch opts) = runOptimizedSearchCommand opts
runCommand (GenSearch opts) = runGenSearchCommand (genSearchLength opts) (genSearchUseHeuristics opts) (genSearchTrieFile opts) (genSearchPatternFiles opts) (genSearchVerbose opts)
runCommand (Solve opts) = runSolveCommand (solveTaskFile opts) (solveVerbose opts)
runCommand (TestProgram opts) = runTestProgramCommand (testProgramBytes opts)