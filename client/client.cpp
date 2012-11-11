#include <iostream>

#include "boost_helpers.h"
#include "client_results.h"
#include "consts.h"
#include "server_connection.h"

#include <boost/optional.hpp>
#include <boost/program_options.hpp>
#include <boost/asio.hpp>

using namespace std;
namespace po = boost::program_options;
namespace asio = boost::asio;
using boost::asio::ip::tcp;

//////
// Definitions
//////

#define DEFAULT_THREAD_COUNT 2
#define DEFAULT_TASK_REQUEST_COUNT 5

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

   tcp::resolver resolver(io_service);
   tcp::resolver::query query(argv[1], argv[2]);
   tcp::resolver::iterator iterator = resolver.resolve(query);

   server_connection connection(io_service, iterator);

   // TODO create a client that runs with this IO Service and is restrained to a class.
   run_threaded(io_service, thread_count);

	cout << "Program has completed!" << endl;

	return EXIT_SUCCESS;
}
