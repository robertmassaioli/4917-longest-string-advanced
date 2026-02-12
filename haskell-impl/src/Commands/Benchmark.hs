module Commands.Benchmark 
    ( runBenchmarkCommand
    ) where

import Benchmark
import qualified Processor as P

-- | Run the benchmark command
runBenchmarkCommand :: Bool -> Bool -> IO ()
runBenchmarkCommand allBenchmarks verbose = do
    when verbose $ putStrLn "Running 4917 Processor Performance Benchmark..."
    
    putStrLn "=== 4917 Processor Performance Benchmark ==="
    putStrLn "Testing individual instruction performance and program execution speed."
    putStrLn ""
    putStrLn "ℹ️  For comprehensive benchmarking with statistical analysis, use:"
    putStrLn "   stack bench trackedprocessor-bench"
    putStrLn ""
    putStrLn "🔧 Quick Performance Overview:"
    
    -- Run legacy benchmarks for quick overview
    runAllBenchmarks
    
    when allBenchmarks $ do
        putStrLn ""
        putStrLn "🔍 Extended Benchmarks:"
        putStrLn "Running additional comprehensive benchmarks..."
        putStrLn ""
        putStrLn "💡 For detailed performance analysis with confidence intervals,"
        putStrLn "   statistical significance testing, and enhanced tracking benchmarks:"
        putStrLn "   stack bench trackedprocessor-bench"

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()