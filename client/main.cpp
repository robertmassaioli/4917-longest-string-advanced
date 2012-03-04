#include <iostream>
#include <cstdlib>
#include <cstring>
#include "processor.h"

using namespace std;

//////
// Function Prototypes
//////


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

