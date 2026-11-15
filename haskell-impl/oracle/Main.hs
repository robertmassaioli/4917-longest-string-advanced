module Main where

import Control.Monad (unless)
import Data.List (intercalate)
import qualified Data.Vector.Unboxed as V
import Processor
import System.IO (isEOF)

main :: IO ()
main = loop
  where
    loop = do
      done <- isEOF
      unless done $ do
        line <- getLine
        putStrLn (oracle line)
        loop

oracle :: String -> String
oracle line = case break (== '|') line of
  (programText, '|':limitText) -> case (mapM parseNibble (split ',' programText), reads limitText :: [(Int, String)]) of
    (Just values, [(limit, "")]) -> render values (max 0 limit)
    _ -> "invalid"
  _ -> "invalid"
  where
    render values limit =
      let initial = initProgram (createDevice values)
          (final, steps, output, halted) = go initial limit 0 []
          status = if halted then "halted" else "step_limit"
      in intercalate "\t"
          [ status, show steps, intercalate "," (map show (reverse output))
          , intercalate "," (map show (V.toList (memory final) :: [Byte]))
          , show (r0 final), show (r1 final), show (pc final), show (outputCount final) ]
    go :: Device -> Int -> Int -> [Int] -> (Device, Int, [Int], Bool)
    go state remaining steps output
      | remaining == 0 = (state, steps, output, False)
      | otherwise =
          let (next, info, halted) = stepProgram state
              emitted = if info == NoOutput then output else fromIntegral (memory state V.! fromIntegral ((pc state + 1) `mod` 16)) : output
          in if halted then (next, steps + 1, emitted, True)
             else go next (remaining - 1) (steps + 1) emitted

split :: Char -> String -> [String]
split delimiter input = case break (== delimiter) input of
  (part, []) -> [part]
  (part, _:rest) -> part : split delimiter rest

parseNibble :: String -> Maybe Byte
parseNibble text = case reads text of
  [(value, "")] | value >= (0 :: Int) && value <= 15 -> Just (fromIntegral value)
  _ -> Nothing
