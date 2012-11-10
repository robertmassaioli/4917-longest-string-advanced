#ifndef __4917_TASK_MANAGER
#define __4917_TASK_MANAGER

#include <boost/smart_ptr.hpp>
#include <set>
#include "task_generator.h"
#include "message.h"

/**
 * The purpose of this task is to manage the tasks that a client is currently supposed to
 * be processing.
 */
class task_manager
{
   public:
      /**
       * The task manager wraps a taskGenerator and handles everything about it.
       * \param taskGenerator This will be used to acquire and return tasks.
       */
      task_manager(boost::shared_ptr<TaskGenerator> taskGenerator);

      /**
       * The destructor will release any unfinished tasks back to the TaskGenerator.
       */
      ~task_manager();

      /**
       * Requests a number of tasks from the TaskGenerator and then wraps them in a
       * message_task_response.
       * 
       * \param tasksRequested This is how many tasks were requested. It does not mean
       * that this is how many tasks will be returned in the result. There may not be that
       * many tasks left after all.
       *
       * \return A message task response which you could send back to the client.
       */
      boost::shared_ptr<message_task_response> acquireTasks(short tasksRequested);

      /**
       * When a task has been SUCCESSFULLY completed then you can use this function to
       * mark it as such.
       *
       * \param task The task to be marked as successful.
       */
      bool task_finished(uint32_t task);

   private:
      boost::shared_ptr<TaskGenerator> taskGenerator;
      std::set<uint32_t> ownedTasks;
};

#endif
