#include <iostream>
#include <cstdlib>
#include <cstring>
#include <queue>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>

#include "processor.h"
#include "task_queue.h"
#include "consts.h"
#include "common.h"

#include <boost/thread.hpp>
#include <boost/optional.hpp>
#include <boost/program_options.hpp>
#include <boost/asio.hpp>
#include <boost/smart_ptr/shared_ptr.hpp>
#include <boost/smart_ptr/make_shared.hpp>

using namespace std;
namespace po = boost::program_options;
namespace asio = boost::asio;

//////
// Private Classes
//////

class ServerDetails {
   public:
      int socketFD;
      boost::shared_ptr<TaskQueue> taskQueue;
};

//////
// Function Prototypes
//////

static void serverConnect(ServerDetails* details);
static void solveTask(void);

//////
// Definitions
//////

#define MAX_LEVEL	11
#define DEFAULT_THREAD_COUNT 2
#define DEFAULT_TASK_REQUEST_COUNT 5

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

//////
// Beginning of program code
//////

int main(int argc, char** argv) {
   boost::optional<string> username = get_env("USER");
   if(username) {
      cout << "Welcome " << *username << " to the 4917 distributed client!" << endl;
   }

   // parse the program options
   int thread_count;
   po::options_description desc("Program options", DESCRIPTION_WIDTH);
   desc.add_options()
      (
         "help,h", 
         "produce help message"
      )
      (
         "threads,n", 
         po::value<int>(&thread_count)->default_value(DEFAULT_THREAD_COUNT),
         "the number of threads on this computer to use for calculation"
      )
      ;

   po::variables_map vm;
   po::store(po::parse_command_line(argc, argv, desc), vm);
   po::notify(vm);

   if (vm.count("help")) {
      cout << desc << endl;
      return EXIT_SUCCESS;
   }

   asio::io_service io_service;

   // TODO create a client that runs with this IO Service and is restrained to a class.
   io_service.run();

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

   // Now ask for a task
   const size_t buffLen = 100;
   byte buffer[buffLen];
   buffer[0] = 1; // TODO this is the message type. Create a shared enum
   buffer[1] = 5; // This is the number of tasks being requested. Make nicer.
   send(socketFD, buffer, 2, 0); // send two bytes down the pipe

   // Temporary code to start doing the networking work.
   close(socketFD);
   exit(0);

   boost::shared_ptr<TaskQueue> tasks = boost::make_shared<TaskQueue>();

   ServerDetails* serverDetails = new ServerDetails();
   serverDetails->socketFD = socketFD;
   serverDetails->taskQueue = tasks;
   boost::thread serverConnection(serverConnect, serverDetails);

   boost::thread_group workers;
   for(int i = 0; i < thread_count; ++i) {
      workers.create_thread(solveTask);
   }

   // Wait for all of the workers to end then shut down the server.
   workers.join_all();
   serverConnection.join();

	cout << "Program has completed!" << endl;

	return EXIT_SUCCESS;
}

static bool closeClient = false;
static boost::mutex closeClientLock;
static bool serverDisconnect = false;
static boost::mutex serverDisconnectLock;

static bool continueRunningServer() {
   closeClientLock.lock();
   serverDisconnectLock.lock();
   bool continueRunning = !(closeClient || serverDisconnect);
   closeClientLock.unlock();
   serverDisconnectLock.unlock();
   return continueRunning;
}

static void serverConnect(ServerDetails* details) {
   // Until the server connection dies or the user aborts the client
   while(continueRunningServer()) {
      // If you need more tasks then ask for them
      if(details->taskQueue->requiresMoreTasks()) {
      }
      // Listen to the responses from the server and process them
   }

   delete details;
}

static void solveTask(void) {
   // TODO this is the task solving code. Throw it into a new thread so that we can run it really
   // efficiently. It should also be in its own function. This can probably be executed really well
   // by using boost futures in the boost::thread library.
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
}
