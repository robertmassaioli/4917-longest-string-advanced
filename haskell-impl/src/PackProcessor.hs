{-# LANGUAGE RecordWildCards #-}

module PackProcessor
    ( packHalfDevice
    , unpackHalfDevice
    , packDevice
    , unpackDevice
    ) where

import Data.Word (Word32, Word64)
import Data.Bits ((.&.), (.|.), shiftL, shiftR)
import Data.Vector.Unboxed ((!))
import Processor (Device(..), createDevice)

-- | Pack the first 8 memory locations (half device) into a 32-bit word
-- Each memory location is 4 bits, so 8 locations = 32 bits
packHalfDevice :: Device -> Word32
packHalfDevice Device{..} = 
    let packByte i = fromIntegral (memory ! i) .&. 0x0F
        packed = foldr (\i acc -> acc .|. (packByte i `shiftL` (i * 4))) 0 [0..7]
    in packed

-- | Unpack 32 bits into the first 8 memory locations of a device
unpackHalfDevice :: Word32 -> Device
unpackHalfDevice packed = 
    let extractNibble i = fromIntegral ((packed `shiftR` (i * 4)) .&. 0x0F)
        memoryList = [extractNibble i | i <- [0..7]] ++ replicate 8 0
    in createDevice memoryList

-- | Pack entire device (16 memory locations) into a 64-bit word  
-- Each memory location is 4 bits, so 16 locations = 64 bits
packDevice :: Device -> Word64
packDevice Device{..} = 
    let packByte i = fromIntegral (memory ! i) .&. 0x0F
        packed = foldr (\i acc -> acc .|. (packByte i `shiftL` (i * 4))) 0 [0..15]
    in packed

-- | Unpack 64 bits into all 16 memory locations of a device
unpackDevice :: Word64 -> Device
unpackDevice packed = 
    let extractNibble i = fromIntegral ((packed `shiftR` (i * 4)) .&. 0x0F)
        memoryList = [extractNibble i | i <- [0..15]]
    in createDevice memoryList