#include <iostream>
#include <cstdlib>
#include <cstring>

using namespace std;

typedef unsigned char byte;

/*
 * I am going to make this program multithreaded. I just need one semaphore to connect
 * the creation of new programs with the threads that consume them and then I will be able
 * to make it work quite easily.
 */

struct device {
	byte memory[16];
	byte R0, R1, PC;
};

//////
// Function Prototypes
//////

int run_program(struct device* program, int timeout);
int run_program_loop_check(struct device* program);
int init_program(struct device* program);
int step_program(struct device* program, bool* programFinished);
void copy_program(struct device* dst, struct device* src);
bool compare_programs(struct device* one, struct device* two);

//////
// Definitions
//////

#define MAX_LEVEL	11
#define TIMEOUT		0x800

//////
// Beginning of program code
//////

int main(int argc, char** argv) {
	// use memcpy to copy devices
   pthread_mutex_t longestEditMutex = PTHREAD_MUTEX_INITIALIZER;
	struct device runner, currentProgram, longestProgram;
	int longestCount = 0, tempCount;

	memset(&currentProgram, 0, sizeof(struct device));
	currentProgram.memory[MAX_LEVEL - 1] = 1;

	while(true) {
		int counter = 0;
		int temp = 0;
		while(temp == 0 && counter < MAX_LEVEL) {
			temp = currentProgram.memory[counter];
			temp = (temp + 1) & 0x0F;
			currentProgram.memory[counter] = temp;
			counter++;
         if(counter > 6) {
            cout << "Reached: ";
            for(int i = 0; i < 16; ++i) {
               cout << (int) currentProgram.memory[i] << ' ';
            }
            cout << endl;
         }
		}
		if(counter == MAX_LEVEL) break;

      tempCount = run_program_loop_check(&currentProgram);
		if(tempCount > longestCount) {
			longestCount = tempCount;
			memcpy(&longestProgram, &currentProgram, sizeof(struct device));
			cout << "New Longest: ";
			for(int i = 0; i < 16; ++i) {
				cout << (int) longestProgram.memory[i] << ' ';
			}
			cout << " is the longest at " << longestCount << endl;
		}
	}

	cout << "Program has completed!" << endl;

	return EXIT_SUCCESS;
}

/*
	This is runs the program and prints out the result.
*/
int run_program(struct device* program, int timeout) {
	bool programFinished = false;
	int outputCount = 0;

   init_program(program);
	while (!programFinished && timeout != 0) {
      outputCount += step_program(program, &programFinished);
		timeout--;
	}

	if(timeout == 0) return 0;
	return outputCount;
}

/**
 * This function promises not to make any edits to the program that is passed in.
 */
int run_program_loop_check(struct device* program) {
   struct device slow_program, fast_program;

   copy_program(&slow_program, program);
   copy_program(&fast_program, program);

   init_program(&slow_program);
   init_program(&fast_program);
   bool fastProgramFinished = false, slowProgramFinished = false;
   int outputCount = 0;
   while (!fastProgramFinished) {
      step_program(&slow_program, &slowProgramFinished);
      outputCount += step_program(&fast_program, &fastProgramFinished);
      if(!fastProgramFinished) outputCount += step_program(&fast_program, &fastProgramFinished);
      if(compare_programs(&slow_program, &fast_program)) {
         return 0;
      }
   }
   return outputCount;
}

int init_program(struct device* program) {
   program->R0 = program->R1 = program->PC = 0;
}

int step_program(struct device* program, bool* programFinished) {
   bool incPC = true;

   int outputCount = 0;
   switch(program->memory[program->PC]) {
		case 0:
			*programFinished = true;
			break;

		case 1:
			program->R0 += program->R1;
			program->R0 &= 0x0F;
			break;

		case 2:
			program->R0 -= program->R1;
			program->R0 &= 0x0F;
			break;

		case 3:
			program->R0++;
			program->R0 &= 0x0F;
			break;

		case 4:
			program->R1++;
			program->R1 &= 0x0F;
			break;

		case 5:
			program->R0--;
			program->R0 &= 0x0F;
			break;

		case 6:
			program->R1--;
			program->R1 &= 0x0F;
			break;

		case 7:
			break;

		case 8:
			program->PC = (program->PC + 1) & 0x0F;
			if(program->memory[program->PC] > 9) {
				outputCount += 2;
			} else {
				outputCount++;
			}
			break;

		case 9:
			program->PC = (program->PC + 1) & 0x0F;
			program->R0 = program->memory[program->memory[program->PC]];
			break;

		case 10:
			program->PC = (program->PC + 1) & 0x0F;
			program->R1 = program->memory[program->memory[program->PC]];
			break;

		case 11:
			program->PC = (program->PC + 1) & 0x0F;
			program->memory[program->memory[program->PC]] = program->R0;
			break;

		case 12:
			program->PC = (program->PC + 1) & 0x0F;
			program->memory[program->memory[program->PC]] = program->R1;
			break;

		case 13:
			program->PC = (program->PC + 1) & 0x0F;
			program->PC = program->memory[program->PC];
			incPC = false;
			break;

		case 14:
			program->PC = (program->PC + 1) & 0x0F;
			if(program->R0 == 0) {
				program->PC = program->memory[program->PC];
				incPC = false;
			}
			break;

		case 15:
			program->PC = (program->PC + 1) & 0x0F;
			if(program->R0 != 0) {
				program->PC = program->memory[program->PC];
				incPC = false;
			}
			break;
   }

   // prepare for the next loop
   if(incPC) {
      program->PC = (program->PC + 1) & 0x0F;
   }
   return outputCount;
}

/**
 * Copy everything in the src program to the destination program
 */
void copy_program(struct device* dst, struct device* src) {
   memcpy(dst, src, sizeof(struct device));
}

/**
 * Compare the two program states exactly.
 *
 * return true if they are exactly equal and false if they are not.
 */
bool compare_programs(struct device* one, struct device* two) {
   if(one->PC != two->PC) return false;
   if(one->R0 != two->R0) return false;
   if(one->R1 != two->R1) return false;

   // There are sixteen memory locations, check all of them.
   for(int i = 0; i < 0x0F; ++i) {
      if(one->memory[i] != two->memory[i]) return false;
   }
   return true;
}
