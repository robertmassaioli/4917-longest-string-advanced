#ifndef __4917_TASK_QUEUE
#define __4917_TASK_QUEUE

#include <queue>

#include <boost/thread/mutex.hpp>
#include <boost/optional/optional.hpp>

/**
 * \brief Manages the tasks for a client and lets people know when more should be
 * requested.
 *
 * This class manages all of the tasks that the server gives it and prepares to run them
 * all in their own threads.
 */
class task_queue {
   private:
      std::queue<uint64_t> tasks;
      boost::mutex tasksLock;

   public:
      void addTask(uint64_t task);
      boost::optional<uint64_t> tryGetTask(void);  
      bool requiresMoreTasks(void);
};

#endif
