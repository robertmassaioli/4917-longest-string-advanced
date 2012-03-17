#ifndef __4917_TASK_QUEUE
#define __4917_TASK_QUEUE

#include <queue>

#include <boost/thread/mutex.hpp>
#include <boost/optional/optional.hpp>

class TaskQueue {
   private:
      std::queue<uint64_t> tasks;
      boost::mutex tasksLock;

   public:
      void addTask(uint64_t task);
      boost::optional<uint64_t> tryGetTask(void);  
      bool requiresMoreTasks(void);
};

#endif
