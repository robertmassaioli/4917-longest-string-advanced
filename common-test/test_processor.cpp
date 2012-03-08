#include <gtest/gtest.h>
#include "processor.h"

class ProcessorTest : public ::testing::Test {
   protected:
      virtual void SetUp() {
         begin = (struct device*) malloc(sizeof(struct device));
         end = (struct device*) malloc(sizeof(struct device));

         for(int i = 0; i < 16; ++i) begin->memory[i] = 0;
         init_program(begin);
         finished = false;
      }

      virtual void TearDown() {
         free(begin);
         free(end);
      }

      struct device* begin;
      struct device* end;
      bool finished;
};


TEST_F(ProcessorTest, CommandZero) {
   begin->memory[0] = 0;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

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

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(10, end->R0);
   EXPECT_EQ(7, end->R1);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R0 = 3;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandOneWrap) {
   begin->memory[0] = 1;
   begin->R0 = 10;
   begin->R1 = 7;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(1, end->R0);
   EXPECT_EQ(7, end->R1);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R0 = 10;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandTwo) {
   begin->memory[0] = 2;
   begin->R0 = 6;
   begin->R1 = 2;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(4, end->R0);
   EXPECT_EQ(2, end->R1);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R0 = 6;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandThree) {
   begin->memory[0] = 3;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(1, end->R0);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R0 = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandFour) {
   begin->memory[0] = 4;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(1, end->R1);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R1 = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandFive) {
   begin->memory[0] = 5;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(15, end->R0);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R0 = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandSix) {
   begin->memory[0] = 6;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(15, end->R1);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R1 = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandSeven) {
   begin->memory[0] = 7;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandEightSingleDigit) {
   begin->memory[0] = 8;
   begin->memory[1] = 3;
   copy_program(end, begin);

   EXPECT_EQ(1, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandEightDoubleDigit) {
   begin->memory[0] = 8;
   begin->memory[1] = 13;
   copy_program(end, begin);

   EXPECT_EQ(2, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandNine) {
   begin->memory[0] = 9;
   begin->memory[1] = 0;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(9, end->R0);
   EXPECT_EQ(2, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R0 = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandTen) {
   begin->memory[0] = 10;
   begin->memory[1] = 0;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(10, end->R1);
   EXPECT_EQ(2, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->R1 = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandEleven) {
   begin->memory[0] = 11;
   begin->memory[1] = 0;
   begin->R0 = 7;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(7, end->memory[0]);
   EXPECT_EQ(0, end->memory[1]);
   EXPECT_EQ(2, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->memory[0] = 11;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandTwelve) {
   begin->memory[0] = 12;
   begin->memory[1] = 0;
   begin->R1 = 7;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(7, end->memory[0]);
   EXPECT_EQ(0, end->memory[1]);
   EXPECT_EQ(2, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   end->memory[0] = 12;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandThirteenBasic) {
   begin->memory[0] = 13;
   begin->memory[1] = 0;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(0, end->PC);
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandThirteenReal) {
   begin->memory[0] = 13;
   begin->memory[1] = 12;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(12, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandFourteenConditionFalse) {
   begin->memory[0] = 14;
   begin->memory[1] = 12;
   begin->R0 = 5;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(2, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandFourteenConditionTrue) {
   begin->memory[0] = 14;
   begin->memory[1] = 12;
   begin->R0 = 0;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(12, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandFifteenConditionFalse) {
   begin->memory[0] = 15;
   begin->memory[1] = 12;
   begin->R0 = 0;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(2, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}

TEST_F(ProcessorTest, CommandFifteenConditionTrue) {
   begin->memory[0] = 15;
   begin->memory[1] = 12;
   begin->R0 = 8;
   copy_program(end, begin);

   EXPECT_EQ(0, step_program(end, &finished));

   EXPECT_FALSE(finished);
   EXPECT_EQ(12, end->PC);

   EXPECT_FALSE(compare_programs(begin, end));
   end->PC = 0;
   EXPECT_TRUE(compare_programs(begin, end));
}
