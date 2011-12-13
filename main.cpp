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

int run_program(struct device* program, int timeout);

#define MAX_LEVEL	11
#define TIMEOUT		0x400

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
		}
		if(counter == MAX_LEVEL) break;

		memcpy(&runner, &currentProgram, sizeof(struct device));
		tempCount = run_program(&runner, TIMEOUT);
		if(tempCount > longestCount) {
			longestCount = tempCount;
			memcpy(&longestProgram, &currentProgram, sizeof(struct device));
			cout << "New Longest: ";
			for(int i = 0; i < 16; ++i) {
				//if(longestProgram.memory[i] == 0) break;
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
	bool incPC = true;
	int outputCount = 0;
	program->R0 = program->R1 = program->PC = 0;

	while (!programFinished && timeout != 0) {
		switch(program->memory[program->PC]) {
		case 0:
			programFinished = true;
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
		if(incPC) program->PC = (program->PC + 1) & 0x0F;
		incPC = true;
		timeout--;
	}

	if(timeout == 0) return 0;
	return outputCount;
}
