#include <gtest/gtest.h>
#include "processor.h"

TEST(Processor, CommandZero) {
   struct device begin, end;
   begin.memory[0] = 0;
   init_program(&begin);
   copy_program(&end, &begin);

   bool finished = false;
   step_program(&end, &finished);

   // Expect the program to be finished after running zero
   EXPECT_TRUE(finished);
   // Expect the program counter to be incremented by one
   EXPECT_EQ(begin.PC + 1, end.PC);
   // If we reset the program counter then expect nothing else to have changed
   end.PC = begin.PC;
   EXPECT_TRUE(compare_programs(&begin, &end)); 
}
