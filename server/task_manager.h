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
      task_manager(boost::shared_ptr<TaskGenerator> taskGenerator);
      ~task_manager();

      boost::shared_ptr<message_task_response> acquireTasks(short tasksRequested);

      bool task_finished(uint32_t task);

   private:
      boost::shared_ptr<TaskGenerator> taskGenerator;
      std::set<uint32_t> ownedTasks;
};

#endif
