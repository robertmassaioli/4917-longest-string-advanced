#ifndef __4917_TASK_GENERATOR
#define __4917_TASK_GENERATOR

#include <stdint.h>
#include <stack>

class TaskGenerator {
   public:
      uint32_t getNextTask(void);
      void returnFailedTask(uint32_t failedTask);
      bool haveNextTask(void);

   private:
      std::stack<uint32_t> failedTasks;
      uint32_t nextTask;
};

#endif
