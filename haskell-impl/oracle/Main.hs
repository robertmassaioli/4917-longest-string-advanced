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
oracle line = case split '|' line of
  ["run", programText, limitText] -> case (mapM parseNibble (split ',' programText), reads limitText :: [(Int, String)]) of
    (Just values, [(limit, "")]) -> render values (max 0 limit)
    _ -> "invalid"
  ["step", memoryText, r0Text, r1Text, pcText, outputText] ->
    case (mapM parseNibble (split ',' memoryText), reads r0Text :: [(Int, String)],
          reads r1Text :: [(Int, String)], reads pcText :: [(Int, String)],
          reads outputText :: [(Int, String)]) of
      (Just cells, [(register0, "")], [(register1, "")], [(counter, "")], [(output, "")])
        | length cells == 16 && all (\n -> n >= 0 && n <= 15) [register0, register1, counter] && output >= 0 ->
            renderStep cells register0 register1 counter output
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
    renderStep cells register0 register1 counter output =
      let initial = Device (V.fromList cells) (fromIntegral register0) (fromIntegral register1)
                      (fromIntegral counter) output
          (final, info, halted) = stepProgram initial
          value = if info == NoOutput then "" else show (memory initial V.! fromIntegral ((pc initial + 1) `mod` 16))
      in intercalate "\t"
          [ value, show halted, intercalate "," (map show (V.toList (memory final) :: [Byte]))
          , show (r0 final), show (r1 final), show (pc final), show (outputCount final) ]

split :: Char -> String -> [String]
split delimiter input = case break (== delimiter) input of
  (part, []) -> [part]
  (part, _:rest) -> part : split delimiter rest

parseNibble :: String -> Maybe Byte
parseNibble text = case reads text of
  [(value, "")] | value >= (0 :: Int) && value <= 15 -> Just (fromIntegral value)
  _ -> Nothing
