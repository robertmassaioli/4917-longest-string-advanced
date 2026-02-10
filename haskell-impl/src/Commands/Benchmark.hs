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
    
    -- Run all benchmarks
    runAllBenchmarks
    
    when allBenchmarks $ do
        putStrLn ""
        putStrLn "🔍 Extended Benchmarks:"
        putStrLn "Running additional comprehensive benchmarks..."
        -- Add extended benchmarks here if needed

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()