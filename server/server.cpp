#include <iostream>
#include <cstdlib>

#include "consts.h"
#include "task_generator.h"
#include "client_connection.h"
#include "boost_helpers.h"
#include "common.h"

#include <boost/asio.hpp>
#include <boost/program_options.hpp>

using namespace std;
using boost::asio::ip::tcp;
namespace po = boost::program_options;
namespace asio = boost::asio;

#define DEFAULT_THREAD_COUNT  4
#define MAX_CONNECTIONS       100
#define DEFAULT_PORT          "9999"

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
