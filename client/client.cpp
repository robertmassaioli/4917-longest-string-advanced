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
using boost::asio::ip::tcp;
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

class server_connection
{
   public:
      server_connection(asio::io_service& io_service,
                        tcp::resolver::iterator endpoint_iterator)
         : io_service_(io_service), socket_(io_service)
      {
          boost::asio::async_connect(socket_, endpoint_iterator,
              boost::bind(&server_connection::handle_connect, this,
                boost::asio::placeholders::error));
      }

   private:
      void handle_connect(const boost::system::error_code& error) {
         cout << "We made a connection to the server! Success!" << endl;
      }

      // The underlying socket that we use for communication.
      tcp::socket socket_;
      asio::io_service& io_service_;
};

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

   tcp::resolver resolver(io_service);
   tcp::resolver::query query(argv[1], argv[2]);
   tcp::resolver::iterator iterator = resolver.resolve(query);

   server_connection connection(io_service, iterator);

   // TODO create a client that runs with this IO Service and is restrained to a class.
   io_service.run();

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
