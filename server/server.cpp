#include <iostream>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <poll.h>

#include "consts.h"
#include "common.h"
#include "message.h"
#include "connection.h"
#include "task_generator.h"
#include "task_manager.h"
#include "client_results.h"
#include "boost_helpers.h"

#include <boost/ref.hpp>
#include <boost/asio.hpp>
#include <boost/optional.hpp>
#include <boost/smart_ptr.hpp>
#include <boost/make_shared.hpp>
#include <boost/program_options.hpp>
#include <boost/thread/thread.hpp>
#include <boost/thread/mutex.hpp>
#include <boost/archive/text_oarchive.hpp>

using namespace std;
using boost::asio::ip::tcp;
namespace po = boost::program_options;
namespace asio = boost::asio;
namespace ip = boost::asio::ip;

typedef unsigned char byte;

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

#define DEFAULT_THREAD_COUNT 4
#define MAX_CONNECTIONS    100
#define DEFAULT_PORT       "9999"

// TODO the message_queue is not thread safe at all. Make it so that it is.
class client_connection 
   : public boost::enable_shared_from_this<client_connection>
{
   public:
      typedef boost::shared_ptr<client_connection> pointer;

      static pointer create(asio::io_service& io_service, boost::shared_ptr<TaskGenerator> tg) {
         return pointer(new client_connection(io_service, tg));
      }

      tcp::socket& socket() {
         return connection_.socket();
      }

      void run() {
         wait_for_request();
         // This essentially runs the client and attempts to keep it in contact with the target
         // machine. In here is where we do all of the complicated messaging and handling.

         // Kick off a read async task for anything that the client might want to send us
         // Kick off a periodic status update task that the client can return to us
      }


   private:
      client_connection(asio::io_service& io_service, boost::shared_ptr<TaskGenerator> taskGenerator)
         : connection_(io_service)
         , client_strand(io_service)
         , outbound_queue(&client_strand, &connection_) 
         , taskManager(new task_manager(taskGenerator))
      {
         // WARNING: The client is not connected here. They only connect as of the run function.
      }

      void wait_for_request() 
      {
         cout << "# Started waiting for a request" << endl;
         connection_.async_read(header, 
               //client_strand.wrap(
                  boost::bind(
                     &client_connection::handle_header,
                     shared_from_this(),
                     asio::placeholders::error
                  )
               //)
            );
      }

      void handle_header(const boost::system::error_code& ec)
      {
         if(ec) 
         {
            cout << "Error parsing the header: " << ec.message() << endl;
         }
         else
         {
            cout << "Recieved header type: " << header.type << endl;
            if(header.type == message_header::REQUESTING_TASKS)
            {
                  cout << "The client is requesting tasks." << endl;
                  boost::shared_ptr<message_task_request> mtr(new message_task_request);
                  connection_.async_read(*mtr.get(),
                        boost::bind(
                           &client_connection::handle_task_request,
                           shared_from_this(),
                           mtr,
                           asio::placeholders::error
                           )
                        );
            }
            else if(header.type == message_header::POST_BACK_DATA)
            {
               cout << "The client is posting us their results" << endl;
               boost::shared_ptr<client_results> cr(new client_results(0));
               connection_.async_read(*cr.get(),
                     boost::bind(
                        &client_connection::handle_results,
                        shared_from_this(),
                        cr,
                        asio::placeholders::error
                        )
                     );
            }
            else if (header.type == message_header::STATUS_UPDATE)
            {
               cout << "The client is giving us a status update." << endl;
            } 
            else
            {
               cout << "Not a valid header type: " << header.type << endl;
            }
         }
      }

      void handle_data(const boost::system::error_code& ec)
      {
      }

      void handle_write(const boost::system::error_code& ec) 
      {
         // do nothing for now
      }

      void handle_task_request(boost::shared_ptr<message_task_request> mt_request, const boost::system::error_code& ec) 
      {
         // The client is requesting more tasks. Give them more.
         if(ec) 
         {
            cout << "There was an error parsing the task request: " << ec.message() << endl;
         }
         else
         {
            cout << "We got the task request: " << mt_request->getTasksRequested() << endl;

            // Get the tasks for the client.
            boost::shared_ptr<message_task_response> mt_response = taskManager->acquireTasks(mt_request->getTasksRequested());
            cout << "Responding with tasks: " << mt_response->getTasks().size() << endl;

            // Send the tasks back to the client
            message_header mt_response_header(message_header::REQUESTING_TASKS);
            boost::shared_ptr<message_container> mc 
               = boost::make_shared<message_container>(&mt_response_header, mt_response.get());
            outbound_queue.add(mc);

            wait_for_request();
         }
      }

      void handle_results(boost::shared_ptr<client_results> clientResults, const boost::system::error_code& ec) 
      {
         // The client is handing us the results, deal with them. This is a reduce function.
         if(ec)
         {
            cout << "There was an error parsing the results: " << ec.message() << endl;
         }
         else
         {
            cout << "Returning Task: " << clientResults->getTask() << endl;

            // Try and sift the results to find the best results
            for(int i = 1; i <= 16; ++i) 
            {
               cout << "Program Length " << i
                    << " | Longest " << clientResults->getLongestProgram(i)
                    << " | Characters " << clientResults->getLongestCharactersPrinted(i) << endl;
            }
            
            // mark this task as done
            wait_for_request();
         } 
      }

      void handle_status_update() 
      {
         // The client has given us a status update. Deal with it and save that data.
      }

      // TODO work out why people use this enum trick?
      enum { header_length = 4 };

      connection connection_;
      message_queue outbound_queue;
      message_header header;
      boost::asio::strand client_strand;
      boost::shared_ptr<task_manager> taskManager;
      // TODO data structure representing last ping
      // list of the current tasks that it has been assigned so that we can reap them when the
      // client disconnects.
};

class accepting_server {
   public:
      typedef boost::shared_ptr<accepting_server> pointer;

      accepting_server(asio::io_service& io_service, short port, boost::shared_ptr<TaskGenerator> taskGenerator) 
         : acceptor_(io_service, tcp::endpoint(tcp::v6(), port))
      {
         this->taskGenerator = taskGenerator;

         cout << "[Starting the server on port " << port << "]" << endl;
         cout << "[Maximum Concurrent Connections: " << acceptor_.max_connections << "]" << endl;
         run_accept();
      }


   private: 
      void run_accept() 
      {
         client_connection::pointer new_connection = 
            client_connection::create(acceptor_.get_io_service(), taskGenerator);

         acceptor_.async_accept(new_connection->socket(), 
            boost::bind(&accepting_server::handle_accept, 
               this, 
               new_connection,
               asio::placeholders::error));
      }

      void handle_accept(boost::shared_ptr<client_connection> new_connection, 
            const boost::system::error_code& error) 
      {
         if(!error) {
            cout << "Accepting a new client connection" << endl;
            new_connection->run();
         } else {
            cout << "There was an error: " << error.message() << endl;
         }

         run_accept();
      }

      tcp::acceptor acceptor_;
      boost::shared_ptr<TaskGenerator> taskGenerator;
};

int main(int argc, char** argv) {
   boost::optional<string> username = get_env("USER");
   if(username) {
      cout << "Welcome " << *username << " to the 4917 distributed server!" << endl;
   }

   // parse the program options
   int max_connections;
   int thread_count;
   string port;
   po::options_description desc("Program options", DESCRIPTION_WIDTH);
   desc.add_options()
      (
         "help,h", 
         "produce help message"
      )
      (
         "max-connections,m", 
         po::value<int>(&max_connections)->default_value(MAX_CONNECTIONS), 
         "the maximum number of client connections to make at any one time"
      )
      (
         "port,p", 
         po::value<string>(&port)->default_value(DEFAULT_PORT), 
         "the port to start the server on"
      )
      (
         "threads,n", 
         po::value<int>(&thread_count)->default_value(DEFAULT_THREAD_COUNT),
         "the number of threads on this server to perform tasks"
      )
      ;

   po::variables_map vm;
   po::store(po::parse_command_line(argc, argv, desc), vm);
   po::notify(vm);

   if (vm.count("help")) {
      cout << desc << endl;
      return EXIT_SUCCESS;
   }

   if(max_connections != MAX_CONNECTIONS) {
      // Currently boost asio seems to ignore this.
      cout << "Max connections set to: " << max_connections << endl;
   }

   boost::shared_ptr<TaskGenerator> taskGenerator = boost::make_shared<TaskGenerator>();

   asio::io_service io_service;
   const short shortPort = (short) atoi(port.c_str());
   accepting_server::pointer server = 
      accepting_server::pointer(new accepting_server(io_service, shortPort, taskGenerator));

   // Accept the SIGINT signal to stop the server.
   asio::signal_set signals(io_service, SIGINT);
   signals.async_wait(boost::bind(&asio::io_service::stop, &io_service));

   // Now actually run the server
   run_threaded(io_service, thread_count);

   cout << "[TODO] Save the current progress to a file to be loaded next time." << endl;

   cout << "[Successfully closed the server]" << endl;
   return EXIT_SUCCESS;
}
