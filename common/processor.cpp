#include <cstring>
#include "processor.h"

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

void copy_program(struct device* dst, struct device* src) {
   memcpy(dst, src, sizeof(struct device));
}

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

int program_length(struct device* program)
{
   for(int i = 15; i >= 0; --i)
   {
      if(program->memory[i] != 0) return i + 1;
   }
   
   return 0;
}
