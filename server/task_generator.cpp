#include "task_generator.h"

// TODO

TaskGenerator::TaskGenerator() {
   finished = false;
   nextTask = 0;
   // TODO download the standard C++ docs to your computer
   //failedTasks.clear();
}

uint32_t TaskGenerator::getNextTask(void) {
   uint32_t returnedTask = nextTask;

   // If we have failed tasks then re-run them.
   // Warning, this could create an over-the-network infinite loop if the task fails every
   // time
   if(failedTasks.size() > 0) {
      returnedTask = failedTasks.top();
      failedTasks.pop();
      return returnedTask;
   }

   // It is a new task so increment the old one
   nextTask += 1;
   if(nextTask == 0) finished = true;

   return returnedTask;
}

void TaskGenerator::returnFailedTask(uint32_t failedTask) {
   failedTasks.push(failedTask);
}

bool TaskGenerator::haveNextTask(void) {
   return !finished;
}
