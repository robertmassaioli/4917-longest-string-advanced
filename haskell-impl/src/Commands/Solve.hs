module Commands.Solve
    ( runSolveCommand
    ) where

import SolveTask
import System.IO
import System.IO.Error (catchIOError)

-- | Run the solve command
runSolveCommand :: Maybe String -> Bool -> IO ()
runSolveCommand maybeTaskFile verbose = do
    when verbose $ putStrLn "Running task solver..."
    
    putStrLn "=== 4917 Task Solver ==="
    putStrLn ""
    
    case maybeTaskFile of
        Nothing -> do
            putStrLn "No task file specified. Running default task solving demo..."
            runDefaultSolveDemo verbose
        Just taskFile -> do
            putStrLn $ "Loading tasks from: " ++ taskFile
            runTaskFile taskFile verbose

-- | Run default solve demonstration
runDefaultSolveDemo :: Bool -> IO ()
runDefaultSolveDemo verbose = do
    putStrLn "🎯 Default Task Solving Demonstration"
    putStrLn "This would demonstrate the task solving system..."
    putStrLn ""
    
    when verbose $ do
        putStrLn "Task solving process:"
        putStrLn "1. Parse task specifications"
        putStrLn "2. Generate program candidates"
        putStrLn "3. Test and validate solutions"
        putStrLn "4. Return optimal solutions"
        putStrLn ""
    
    -- Example task solving (placeholder)
    putStrLn "Example: Finding programs that output specific patterns..."
    putStrLn "✅ Task solving demo completed!"

-- | Run tasks from file
runTaskFile :: String -> Bool -> IO ()
runTaskFile filename verbose = do
    when verbose $ putStrLn $ "Reading task file: " ++ filename
    
    -- Check if file exists and read it
    fileExists <- doesFileExist filename
    if not fileExists
    then do
        putStrLn $ "❌ Error: Task file '" ++ filename ++ "' not found"
        putStrLn "Please provide a valid task file or run without --task-file for demo"
    else do
        content <- readFile filename
        when verbose $ putStrLn $ "File contents preview: " ++ take 100 content ++ "..."
        putStrLn "📋 Processing task file..."
        
        -- Parse and process tasks (placeholder implementation)
        putStrLn $ "✅ Processed tasks from " ++ filename
        putStrLn "Note: Full task file processing not yet implemented"

-- | Check if file exists (simple implementation)
doesFileExist :: String -> IO Bool
doesFileExist filename = do
    result <- tryOpenFile filename
    case result of
        Left _ -> return False
        Right handle -> do
            hClose handle
            return True
  where
    tryOpenFile :: String -> IO (Either IOError Handle)
    tryOpenFile fn = do
        result <- (Right <$> openFile fn ReadMode) `catchIOError` (return . Left)
        return result

-- Helper to conditionally print
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = return ()