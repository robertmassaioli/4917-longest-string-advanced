#include <gtest/gtest.h>
#include "client_results.h"
#include "processor.h"

TEST(ClientResults, InitialState)
{
   client_results results(1234);

   EXPECT_EQ(1234, results.getTask());

   for(int i = 1; i <= 16; ++i)
   {
      EXPECT_EQ(0, results.getLongestCharactersPrinted(i));
   }
}

TEST(ClientResults, AddOneResult)
{
   client_results results(1234);
   struct device dev;

   for(int i = 0; i < 16; ++i) {
      dev.memory[i] = i < 7 ? 8 : 0;
   }

   // Yes the implementation is trusting, deal with it. The server verifies results.
   results.addResult(&dev, 120);

   EXPECT_EQ(120, results.getLongestCharactersPrinted(7));
}

TEST(ClientResults, AddMultipleResults)
{
   client_results main(0);
   struct device dev;

   for(int length = 0; length <= 16; ++length)
   {
      for(int slot = 0; slot < 16; ++slot)
      {
         dev.memory[slot] = slot < length ? 8 : 0;
      }

      main.addResult(&dev, length);
   }

   for(int length = 1; length <= 16; ++length) 
   {
      EXPECT_EQ(length, main.getLongestCharactersPrinted(length));
   }
}

TEST(ClientResults, MergeResults)
{
   client_results main(0), other(1234);
   struct device dev;

   for(int length = 0; length <= 16; ++length)
   {
      for(int slot = 0; slot < 16; ++slot)
      {
         dev.memory[slot] = slot < length ? 8 : 0;
      }

      main.addResult(&dev, length);
      other.addResult(&dev, length + 20);
   }

   main.merge(&other);

   for(int length = 1; length <= 16; ++length) 
   {
      EXPECT_EQ(length + 20, main.getLongestCharactersPrinted(length));
   }
}
