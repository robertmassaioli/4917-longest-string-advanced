#include <stdint.h>
#include <stack>

#include "task_generator.h"
#include <gtest/gtest.h>

using namespace std;

TEST(GeneratorTest, InitTask) {
   TaskGenerator gen;

   EXPECT_EQ(0, gen.getNextTask());
   EXPECT_EQ(1, gen.getNextTask());
   EXPECT_EQ(2, gen.getNextTask());
}

TEST(GeneratorTest, FailedTask) {
   TaskGenerator gen;

   uint32_t task = 100;
   stack<uint32_t> grabbedItems;

   // Generate some tasks
   task = gen.getNextTask();
   EXPECT_EQ(0, task);
   grabbedItems.push(task);
   grabbedItems.push(gen.getNextTask());
   grabbedItems.push(gen.getNextTask());
   grabbedItems.push(gen.getNextTask());

   // return a failed task
   EXPECT_EQ(3, grabbedItems.top());
   gen.returnFailedTask(grabbedItems.top());
   grabbedItems.pop();
   
   // Expect the failed task
   task = gen.getNextTask();
   EXPECT_EQ(3, task);
}

/*
 * TODO This test takes far too long. Find a way to speed it up.
TEST(GeneratorTest, SimpleHaveNextTask) {
   TaskGenerator gen;

   uint32_t steps = 0;
   do
   {
      gen.getNextTask();
      if(steps == 0xFFFFFFFF) {
         ASSERT_FALSE(gen.haveNextTask());
      } else {
         ASSERT_TRUE(gen.haveNextTask());
      }
      steps++;
      cout << steps << endl;
   } while (steps != 0);
}
*/

int main(int argc, char** argv) {
   ::testing::InitGoogleTest(&argc, argv);
   return RUN_ALL_TESTS();
}
