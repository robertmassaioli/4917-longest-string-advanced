#include "client.h"

void Client::setCurrentTask(uint32_t task) {
   currentTask = task;
}

uint32_t Client::getCurrentTask(void) {
   return currentTask;
}
