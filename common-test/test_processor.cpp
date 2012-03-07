#include <gtest/gtest.h>
#include "processor.h"

class ProcessorTest : public ::testing::Test {
   protected:
      virtual void SetUp() {
         begin = (struct device*) malloc(sizeof(struct device));
         end = (struct device*) malloc(sizeof(struct device));

         init_program(begin);
      }

      virtual void TearDown() {
         free(begin);
         free(end);
      }

      struct device* begin;
      struct device* end;
};


TEST_F(ProcessorTest, CommandZero) {
   begin->memory[0] = 0;
   copy_program(end, begin);

   bool finished = false;
   step_program(end, &finished);

   // Expect the program to be finished after running zero
   EXPECT_TRUE(finished);
   // Expect the program counter to be incremented by one
   EXPECT_EQ(begin->PC + 1, end->PC);
   // If we reset the program counter then expect nothing else to have changed
   end->PC = begin->PC;
   EXPECT_TRUE(compare_programs(begin, end)); 
}

TEST_F(ProcessorTest, CommandOne) {
   begin->memory[0] = 1;
   begin->R0 = 3;
   begin->R1 = 7;
   copy_program(end, begin);

   bool finished = false;
   step_program(end, &finished);

   EXPECT_FALSE(finished);
   EXPECT_EQ(10, end->R0);
   EXPECT_EQ(7, end->R1);

   end->PC = 0;
   end->R0 = 3;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandOneWrap) {
   begin->memory[0] = 1;
   begin->R0 = 10;
   begin->R1 = 7;
   copy_program(end, begin);

   bool finished = false;
   step_program(end, &finished);

   EXPECT_FALSE(finished);
   EXPECT_EQ(1, end->R0);
   EXPECT_EQ(7, end->R1);

   end->PC = 0;
   end->R0 = 10;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandTwo) {
   begin->memory[0] = 2;
   begin->R0 = 6;
   begin->R1 = 2;
   copy_program(end, begin);

   bool finished = false;
   step_program(end, &finished);

   EXPECT_FALSE(finished);
   EXPECT_EQ(4, end->R0);
   EXPECT_EQ(2, end->R1);

   end->PC = 0;
   end->R0 = 6;
   EXPECT_TRUE(compare_programs(begin, end));
}
