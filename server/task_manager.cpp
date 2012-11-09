#include <iostream>
#include "task_manager.h"

using namespace std;

task_manager::task_manager(boost::shared_ptr<TaskGenerator> taskGenerator) 
{
   this->taskGenerator = taskGenerator;
   ownedTasks.clear();
}

task_manager::~task_manager() 
{
   // Return the tasks back to the taskGenerator
   for(set<uint32_t>::const_iterator it = ownedTasks.begin(); it != ownedTasks.end(); ++it) 
   {
      cout << "Client failed to run task: " << *it << endl;
      taskGenerator->returnFailedTask(*it);
   }
}

boost::shared_ptr<message_task_response> task_manager::acquireTasks(short tasksRequested)
{
   cout << "Requesting " << tasksRequested << " tasks for the client." << endl;

   boost::shared_ptr<message_task_response> mtr = boost::make_shared<message_task_response>();
   for(short i = 0; i < tasksRequested && taskGenerator->haveNextTask(); ++i) 
   {
      uint32_t requestedTask = taskGenerator->getNextTask();
      ownedTasks.insert(requestedTask);
      mtr->addTask(requestedTask);
      cout << "Added task: " << requestedTask << endl;
   }

   return mtr;
}

bool task_manager::task_finished(uint32_t task)
{
   set<uint32_t>::iterator foundTask = ownedTasks.find(task);
   if(foundTask == ownedTasks.end()) 
   {
      cout << "ERROR: We tried to 'finish' a task for a client that was not running that task!" << endl;
   }
   else
   {
      ownedTasks.erase(foundTask);
      cout << "Task successfully erased: " << task << endl;
   }
}
