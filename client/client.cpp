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
#include "message.h"
#include "connection.h"

#include <boost/thread.hpp>
#include <boost/optional.hpp>
#include <boost/program_options.hpp>
#include <boost/asio.hpp>
#include <boost/smart_ptr/shared_ptr.hpp>
#include <boost/smart_ptr/make_shared.hpp>
#include <boost/archive/text_oarchive.hpp>

using namespace std;
using boost::asio::ip::tcp;
namespace po = boost::program_options;
namespace asio = boost::asio;

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
         : io_service_(io_service), connection_(io_service)
      {
          boost::asio::async_connect(connection_.socket(), endpoint_iterator,
              boost::bind(&server_connection::handle_connect, this,
                boost::asio::placeholders::error));
      }

   private:
      void handle_connect(const boost::system::error_code& error) {
         cout << "We made a connection to the server! Success!" << endl;
         // Start waiting for the server to tell us stuff.
         // Request some tasks.
         wait_for_server();
      }

      void wait_for_server() {
         connection_.async_read(header, 
               boost::bind(
                  &server_connection::handle_request,
                  this,
                  boost::asio::placeholders::error
                  ));
      }

      void handle_message_task_response(const boost::system::error_code& error, message_task_response* mtr) 
      {
         if(error)
         {
            cout << "There was a problem reading the message_task_response." << endl;
         } 
         else
         {
            cout << "Successfully read the message task response." << endl;

            int tasks = mtr->getTasks().size();
            cout << "The server gave us " << tasks << " tasks to perform:" << endl;
            for(int i = 0; i < tasks; ++i) 
            {
               cout << " - " << mtr->getTasks()[i] << endl;
            }

            // once you are done wait for the server again
            wait_for_server();
         }

         // TODO once you are done with the mtr remember to delete it.
         delete mtr;
      }

      void handle_request(const boost::system::error_code& error)
      {
         if(error) 
         {
            cout << "There was a problem reading the data..." << endl;
         }
         else 
         {
            cout << "Header Type: " << header.type << endl;
            // Keep in mind that this message is from the server to this client.
            message_task_response* mtr = NULL;
            switch(header.type) {
               case message_header::REQUESTING_TASKS:
                  cout << "The server has given us some tasks to perform." << endl;
                  // Parse the message body
                  mtr = new message_task_response;
                  connection_.async_read(*mtr, 
                        boost::bind(
                           &server_connection::handle_message_task_response,
                           this,
                           boost::asio::placeholders::error,
                           mtr
                           ));
                  break;

               case message_header::POST_BACK_DATA:
                  cerr << "Somebody has made a dunce mistake. You cannot post result data to the client. That makes no sense." << endl;
                  break;

               case message_header::STATUS_UPDATE:
                  cout << "Server Requested Status Update." << endl;
                  // We do not expect any more information. This message only has a body.
                  break;

               default:
                  cerr << "[ERROR] The server send us a header with type '" << header.type << "' which we don't know how to deal with. Closing." << endl;
                  break;
            }
         }
      }

      // The underlying socket that we use for communication.
      connection connection_;
      asio::io_service& io_service_;
      message_header header;
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
