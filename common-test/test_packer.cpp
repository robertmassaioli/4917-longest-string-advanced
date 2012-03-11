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
}

TEST(ProcessorPacker, PackHalfDevice) {
}

TEST(ProcessorPacker, UnpackHalfDevice) {
}
