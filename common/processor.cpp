#include <cstring>
#include "processor.h"

/*
	This is runs the program and prints out the result.
*/
int run_program(struct device* program, int timeout) {
	bool programFinished = false;
	int outputCount = 0;

   init_program(program);
   do {
      outputCount += step_program(program, &programFinished);
		timeout--;
	} while (!programFinished && timeout != 0);

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
   do {
      step_program(&slow_program, &slowProgramFinished);
      outputCount += step_program(&fast_program, &fastProgramFinished);
      if(!fastProgramFinished) outputCount += step_program(&fast_program, &fastProgramFinished);
      if(compare_programs(&slow_program, &fast_program)) {
         return 0;
      }
   } while (!fastProgramFinished);
   return outputCount;
}

int init_program(struct device* program) {
   program->R0 = program->R1 = program->PC = 0;
}

int step_program(struct device* program, bool* programFinished) {
   int outputCount = 0;
   byte instruction = program->memory[program->PC];
	program->PC = (program->PC + 1) & 0x0F;
   switch(instruction) {
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
			if(program->memory[program->PC] > 9) {
				outputCount += 2;
			} else {
				outputCount++;
			}
			program->PC = (program->PC + 1) & 0x0F;
			break;

		case 9:
			program->R0 = program->memory[program->memory[program->PC]];
			program->PC = (program->PC + 1) & 0x0F;
			break;

		case 10:
			program->R1 = program->memory[program->memory[program->PC]];
			program->PC = (program->PC + 1) & 0x0F;
			break;

		case 11:
			program->memory[program->memory[program->PC]] = program->R0;
			program->PC = (program->PC + 1) & 0x0F;
			break;

		case 12:
			program->memory[program->memory[program->PC]] = program->R1;
			program->PC = (program->PC + 1) & 0x0F;
			break;

		case 13:
			program->PC = program->memory[program->PC];
			break;

		case 14:
         program->PC = (program->R0 == 0) ? program->memory[program->PC] : ((program->PC + 1) & 0x0F);
			break;

		case 15:
         program->PC = (program->R0 != 0) ? program->memory[program->PC] : ((program->PC + 1) & 0x0F);
			break;
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
