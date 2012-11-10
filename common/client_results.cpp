#include "client_results.h"
#include "processor.h"
#include "pack_processor.h"

client_results::client_results(uint32_t task)
{
   this->task = task;

   // Clear everything, memset would have probably been faster.
   for(int i = 0; i < 16; ++i) 
   {
      results[i].trial = 0;
      results[i].charactersPrinted = 0;   // This is equivalent to not run.
   }
}

void client_results::addResult(struct device* program, int charactersPrinted)
{
   int programLength = program_length(program); 
   // results[0] is for a program of length 1
   int resultsIndex = programLength - 1;
   if(programLength > 0 && charactersPrinted > results[resultsIndex].charactersPrinted)
   {
      results[resultsIndex].charactersPrinted = charactersPrinted;
      pack_device(&(results[resultsIndex].trial), program);
   }
}

uint32_t client_results::getTask()
{
   return task;
}

uint64_t client_results::getLongestProgram(int programLength)
{
   return results[programLength - 1].trial;
}

int client_results::getLongestCharactersPrinted(int programLength)
{
   return results[programLength - 1].charactersPrinted;
}
