#include <iostream>
#include <cstring>

#include "solve_task.h"
#include "processor.h"
#include "pack_processor.h"

#include <boost/smart_ptr/make_shared.hpp>

using namespace std;

#define MAX_LEVEL	16

static void print_program(struct device* program);

boost::shared_ptr<client_results> solveTask(uint32_t task) 
{
   // TODO this is the task solving code. Throw it into a new thread so that we can run it really
   // efficiently. It should also be in its own function. This can probably be executed really well
   // by using boost futures in the boost::thread library.
	struct device currentProgram;
   boost::shared_ptr<client_results> clientResults = boost::make_shared<client_results>(task);

   // Setup the current program
	memset(&currentProgram, 0, sizeof(struct device));
   unpack_half_device(&currentProgram, task);

   if(currentProgram.memory[0] != 0)
   {
      while(true) {
         int counter = 8;
         int temp = 0;
         while(temp == 0 && counter < MAX_LEVEL) {
            temp = currentProgram.memory[counter];
            temp = (temp + 1) & 0x0F;
            currentProgram.memory[counter] = temp;
            counter++;
            if(counter > 14) {
               cout << "Reached: ";
               print_program(&currentProgram);
               cout << endl;
            }
         }
         if(counter == MAX_LEVEL) break;

         int charactersPrinted = run_program_loop_check(&currentProgram);
         clientResults->addResult(&currentProgram, charactersPrinted);
      }
   }

   return clientResults;
}

static void print_program(struct device* program)
{
   for(int i = 0; i < 16; ++i) 
   {
      cout << (int) program->memory[i] << ' ';
   }
}
