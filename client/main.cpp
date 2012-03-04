#include <iostream>
#include <cstdlib>
#include <cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>

#include "processor.h"

using namespace std;

//////
// Function Prototypes
//////


//////
// Definitions
//////

#define MAX_LEVEL	11

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

//////
// Beginning of program code
//////

int main(int argc, char** argv) {
   // TODO Request which part you would like to do.
   cout << "[Starting Server Connection Attempt]" << endl;
   struct addrinfo hints;
   memset(&hints, 0, sizeof(struct addrinfo));
   hints.ai_family = AF_UNSPEC;
   hints.ai_socktype = SOCK_STREAM;
   hints.ai_protocol = 0;
   hints.ai_flags = AI_PASSIVE;
   hints.ai_canonname = NULL;
   hints.ai_addr = NULL;
   hints.ai_next = NULL;

   struct addrinfo *result = NULL;
   int error = getaddrinfo(argv[1], argv[2], &hints, &result);
   if(error != 0) {
      cerr << "getaddrinfo: " << gai_strerror(error) << endl;
      exit(EXIT_FAILURE);
   }

   int socketFD = -1;
   struct addrinfo *rp = NULL;
   for(rp = result; rp != NULL; rp = rp->ai_next) {
      char result[200];
      const char* inetRes = inet_ntop(rp->ai_socktype, rp->ai_addr, result, 200);
      if(inetRes != NULL) {
         cout << "Attempting to connect a socket at '" << inetRes << "'...";
      } else {
         cout << "Attempting to connect a socket...";
      }
      socketFD = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
      if(socketFD == -1) {
         cout << "socket creation " << failed << endl;
         continue;
      }
      if(connect(socketFD, rp->ai_addr, rp->ai_addrlen) == 0) {
         cout << success << endl;
         break;
      }
      cout << "connection " << failed << endl;
      close(socketFD);
   }

   if(rp == NULL) {
      cerr << "Did not manage to bind any sockets or ports." << endl;
      exit(EXIT_FAILURE);
   }

	// use memcpy to copy devices
   //pthread_mutex_t longestEditMutex = PTHREAD_MUTEX_INITIALIZER;
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

