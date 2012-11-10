#ifndef __4917_CLIENT_RESULTS
#define __4917_CLIENT_RESULTS

#include <stdint.h>

struct run_result
{
   uint64_t trial;
   int charactersPrinted;
};

class client_results
{
   public:
      client_results(uint32_t task);
      void addResult(struct device* program, int charactersPrinted);

      uint32_t getTask();
      uint64_t getLongestProgram(int programLength);
      int getLongestCharactersPrinted(int programLength);

   private:
      uint32_t task;
      struct run_result results[16];
};

#endif
