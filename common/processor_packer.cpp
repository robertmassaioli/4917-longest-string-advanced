#include "pack_processor.h"

// I want to pack the programs such that if I printed out the uint32_t in hexidecimal
// that I could read out what the program was.

void pack_half_device(uint32_t* to, struct device* from) {
   for(int i = 0; i < 8; ++i) {
      uint32_t currentValue = from->memory[i] & 0x0F;
      // Four bits per instruction
      *to = (*to << 4) | currentValue;
   }
}

void unpack_half_device(struct device* to, uint32_t from) {
   for(int i = 7; i >= 0; --i) {
      unsigned char val = from & 0x0F;
      to->memory[i] = val;
      from = (from >> 4);
   }
}

void pack_device(uint64_t* to, struct device* from) {
   for(int i = 0; i < 16; ++i) {
      uint64_t currentValue = from->memory[i] & 0x0F;
      // Four bits per instruction
      *to = (*to << 4) | currentValue;
   }
}

void unpack_device(struct device* to, uint64_t from) {
   for(int i = 15; i >= 0; --i) {
      unsigned char val = from & 0x0F;
      to->memory[i] = val;
      from = (from >> 4);
   }
}
