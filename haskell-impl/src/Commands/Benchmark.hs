module Commands.Benchmark 
    ( runBenchmarkCommand
    ) where

import Benchmark
import qualified Processor as P

-- | Run the benchmark command
runBenchmarkCommand :: Bool -> Bool -> IO ()
runBenchmarkCommand allBenchmarks verbose = do
    when verbose $ putStrLn "Running 4917 Processor Performance Benchmark..."
    
    putStrLn "🚀 4917 Processor Benchmark Options:"
    putStrLn "===================================="
    putStrLn ""
    putStrLn "This command has been modernized! Choose your benchmark approach:"
    putStrLn ""
    putStrLn "1. 📊 NEW: Criterion-based Benchmarks (Recommended)"
    putStrLn "   - Original Processor:     stack bench processor-bench"
    putStrLn "   - TrackedProcessor:       stack bench trackedprocessor-bench"
    putStrLn ""
    putStrLn "2. 📈 Legacy: Console Benchmarks"
    putStrLn "   - Run legacy benchmarks with console output (shown below)"
    putStrLn ""
    putStrLn "Criterion Benchmark Examples:"
    putStrLn "  stack bench processor-bench -- --list                     # Show phases"
    putStrLn "  stack bench processor-bench -- --phase 1                  # Individual instructions"
    putStrLn "  stack bench processor-bench -- --phase 2                  # Comprehensive programs"
    putStrLn "  stack bench trackedprocessor-bench -- --phase 1 --verbose # TrackedProcessor instructions"
    putStrLn ""
    
    if allBenchmarks
        then do
            putStrLn "Running both legacy console benchmarks and suggesting Criterion benchmarks..."
            putStrLn ""
            putStrLn "=== Legacy Console Benchmarks ==="
            runAllBenchmarks
            putStrLn ""
            putStrLn "=== Modern Criterion Benchmarks ==="
            putStrLn "For more detailed performance analysis, run:"
            putStrLn "  stack bench processor-bench          # Original Processor"
            putStrLn "  stack bench trackedprocessor-bench   # TrackedProcessor"
        else do
            putStrLn "🔧 Legacy Performance Overview:"
            putStrLn ""
            runAllBenchmarks
            putStrLn ""
            putStrLn "💡 For detailed performance analysis with confidence intervals,"
            putStrLn "   statistical significance testing, and phase selection:"
            putStrLn "   stack bench processor-bench"
            putStrLn "   stack bench trackedprocessor-bench"

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()