#include <gtest/gtest.h>
#include "pack_processor.h"

TEST(ProcessorPacker, PackWholeDevice) {
   struct device dev;

   for(int i = 0; i < 16; ++i) {
      dev.memory[i] = i;
   }

   uint64_t data;
   pack_device(&data, &dev);

   EXPECT_EQ(0x0123456789ABCDEF, data);
}

TEST(ProcessorPacker, UnpackWholeDevice) {
   uint64_t data = 0x0123456789ABCDEF;

   struct device dev;
   unpack_device(&dev, data);

   for(int i = 0; i < 16; ++i) {
      EXPECT_EQ(i, dev.memory[i]);
   }
}

TEST(ProcessorPacker, PackHalfDevice) {
   struct device dev;

   for(int i = 0; i < 8; ++i) {
      dev.memory[i] = i;
   }

   uint32_t data;
   pack_half_device(&data, &dev);

   EXPECT_EQ(0x01234567, data);
}

TEST(ProcessorPacker, UnpackHalfDevice) {
   uint32_t data = 0x01234567;

   struct device dev;
   unpack_half_device(&dev, data);

   for(int i = 0; i < 8; ++i) {
      EXPECT_EQ(i, dev.memory[i]);
   }
}

/*
TEST(ProcessorPacker, FullBijectiveDevice) {
}

Test(ProcessorPacker, FullBijectiveNumber) {
}

Test(ProcessorPacker, HalfBijectiveDevice) {
}

Test(ProcessorPacker, HalfBijectiveNumber) {
}
*/
