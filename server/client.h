#ifndef __4917_CLIENT
#define __4917_CLIENT


/**
 * This is the client class, it is supposed to represent a connection to the client
 * and manage all of that data correctly. It should do as little processing as possible
 * and be considered more of a data holder.
 */
class Client {
   private:
      time_t   last_ping_time;
      uint32_t currentTask;

   public:
      void setCurrentTask(uint32_t newTask);
      uint32_t getCurrentTask(void);
};

#endif
