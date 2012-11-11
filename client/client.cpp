#include <iostream>
#include <cstdlib>
#include <cstring>
#include <queue>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>

#include "processor.h"
#include "pack_processor.h"
#include "task_queue.h"
#include "consts.h"
#include "common.h"
#include "message.h"
#include "connection.h"
#include "client_results.cpp"

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

static void print_program(struct device* program);
static boost::shared_ptr<client_results> solveTask(uint32_t task);
static void runClient(asio::io_service& io_service);

//////
// Definitions
//////

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
         : io_service_(io_service), 
           connection_(io_service), 
           sender_strand(io_service_),
           outbound_queue(&sender_strand, &connection_)
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
         requestTasks();
      }

      void wait_for_server() 
      {
         cout << "Started waiting for the server to tell me something." << endl;
         connection_.async_read(header, 
               boost::bind(
                  &server_connection::handle_request,
                  this,
                  boost::asio::placeholders::error
                  ));
      }

      void requestTasks() {
         message_header tempHeader;
         tempHeader.type = message_header::REQUESTING_TASKS;
         // TODO configure how many tasks will be requested somewhere.
         message_task_request mtr(2);
         boost::shared_ptr<message_container> mc(new message_container(&tempHeader, &mtr));
         outbound_queue.add(mc);
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
               uint32_t currentTask = mtr->getTasks()[i];
               cout << " - " << currentTask << endl;
               // post each of the tasks
               io_service_.post(
                     boost::bind(
                        &server_connection::perform_task,
                        this,
                        currentTask)
                     );

            }

            // once you are done wait for the server again
            wait_for_server();
         }

         // TODO once you are done with the mtr remember to delete it.
         delete mtr;
      }

      void perform_task(uint32_t task) {
         cout << "Running task: " << task << endl;

         // Solve the task that you have been given
         boost::shared_ptr<client_results> result = solveTask(task);


         // Change the data in a stupid way; please remove TODO
         struct device pretendDevice;
         init_program(&pretendDevice);
         pretendDevice.memory[5] = 1;
         result->addResult(&pretendDevice, 10);

         // Dummy code to print the result to the screen
         for(int i = 1; i <= 16; ++i) 
         {
            cout << "Program Length " << i
                 << " | Longest " << result->getLongestProgram(i)
                 << " | Characters " << result->getLongestCharactersPrinted(i) << endl;
         }

         // Now send the data back to the client.
         message_header results_header(message_header::POST_BACK_DATA);
         boost::shared_ptr<message_container> mc = boost::make_shared<message_container>(&results_header, result.get());
         outbound_queue.add(mc);
      }

      void handle_request(const boost::system::error_code& error)
      {
         if(error) 
         {
            cout << "There was a problem reading the header: " << error.message() << endl;
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
                  wait_for_server();
                  // We do not expect any more information. This message only has a body.
                  break;

               default:
                  cerr 
                     << "[ERROR] The server sent us a header with type '" 
                     << header.type 
                     << "' which we don't know how to deal with. Closing." 
                     << endl;
                  break;
            }
         }
      }

      // The underlying socket that we use for communication.
      connection connection_;
      asio::io_service& io_service_;
      message_header header;
      message_queue outbound_queue;
      asio::strand sender_strand;
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
   runClient(io_service);

	cout << "Program has completed!" << endl;

	return EXIT_SUCCESS;
}

#define MAX_LEVEL	16

static boost::shared_ptr<client_results> solveTask(uint32_t task) {
   // TODO this is the task solving code. Throw it into a new thread so that we can run it really
   // efficiently. It should also be in its own function. This can probably be executed really well
   // by using boost futures in the boost::thread library.
	struct device currentProgram;
   boost::shared_ptr<client_results> clientResults = boost::make_shared<client_results>(task);

   // Setup the current program
	memset(&currentProgram, 0, sizeof(struct device));
   unpack_half_device(&currentProgram, task);

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

   return clientResults;
}

static void print_program(struct device* program)
{
   for(int i = 0; i < 16; ++i) 
   {
      cout << (int) program->memory[i] << ' ';
   }
}

#define THREAD_POOL_SIZE 10

static void runClient(asio::io_service& io_service) 
{
   cout << "Kicking off all of the threads." << endl;

   // Kick off all of the threads;
   std::vector<boost::shared_ptr<boost::thread> > threads;
   for(std::size_t i = 0; i < THREAD_POOL_SIZE; ++i)
   {
      boost::shared_ptr<boost::thread> thread(
            new boost::thread(
               boost::bind(
                  &boost::asio::io_service::run,
                  &io_service
                  )
               )
            );

      threads.push_back(thread);
   }

   cout << "All of the threads have been kicked off." << endl;

   for(std::size_t i = 0; i < threads.size(); ++i)
   {
      threads[i]->join();
   }

   cout << "All threads have finished running." << endl;
}
