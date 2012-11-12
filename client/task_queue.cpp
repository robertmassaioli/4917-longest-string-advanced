#include "task_queue.h"

#include <boost/thread/locks.hpp>

using namespace std;
using namespace boost;

void task_queue::addTask(uint64_t task) {
   unique_lock<mutex> ul(tasksLock);
   tasks.push(task);
}

optional<uint64_t> task_queue::tryGetTask(void) {
   unique_lock<mutex> ul(tasksLock, try_to_lock_t());
   optional<uint64_t> ret(none);
   if(ul.owns_lock()) {
      if(!tasks.empty()) {
         uint64_t value = tasks.front();
         tasks.pop();
         return optional<uint64_t>(value);
      }
   }
   return optional<uint64_t>(none);
}

bool task_queue::requiresMoreTasks(void) {
   unique_lock<mutex> ul(tasksLock);
   return tasks.size() <= 3;
}
