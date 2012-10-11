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

//void handleClient(void* data);

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

#define MAX_CONNECTIONS    100
#define DEFAULT_PORT       "9999"

class client_connection 
   : public boost::enable_shared_from_this<client_connection>
{
   public:
      typedef boost::shared_ptr<client_connection> pointer;

      static pointer create(asio::io_service& io_service) {
         return pointer(new client_connection(io_service));
      }

      tcp::socket& socket() {
         return socket_;
      }

      void run() {
         // This essentially runs the client and attempts to keep it in contact with the target
         // machine. In here is where we do all of the complicated messaging and handling.

         cout << "Running a client" << endl;
         asio::streambuf buffer;
         std::ostream output(&buffer);

         message_header header;
         header.type = message_header::STATUS_UPDATE;

         boost::archive::text_oarchive outArchive(output);
         outArchive << header;

         size_t dataSent = socket_.send(buffer.data());
         buffer.consume(dataSent);
         

         // Wait until the client decides to close and ping the client every so often to make sure
         // that we remain updated with its progress.
      }

   private:
      client_connection(asio::io_service& io_service)
         : socket_(io_service) 
      {
         asio::async_read(socket_, asio::buffer(raw_header_data_), 
               boost::bind(&client_connection::handle_header,
                  this,
                  asio::placeholders::error,
                  asio::placeholders::bytes_transferred));
      }

      void handle_header(const boost::system::error_code& ec, size_t bytes_transferred) {
      }

      void handle_data(const boost::system::error_code& ec, size_t bytes_transferred) {
      }

      void handle_task_request() {
         // The client is requesting more tasks. Give them more.
      }

      void handle_results() {
         // The client is handing us the results, deal with them. This is a reduce function.
      }

      void handle_status_update() {
         // The client has given us a status update. Deal with it and save that data.
      }

      // TODO work out why people use this enum trick?
      enum { header_length = 4 };

      ip::tcp::socket socket_;
      char raw_header_data_[header_length];
      // TODO data structure representing last ping
      // list of the current tasks that it has been assigned so that we can reap them when the
      // client disconnects.
};

class accepting_server {
   public:
      typedef boost::shared_ptr<accepting_server> pointer;

      accepting_server(asio::io_service& io_service, short port) 
         : acceptor_(io_service, tcp::endpoint(tcp::v6(), port))
      {
         cout << "[Starting the server on port " << port << "]" << endl;
         cout << "[Maximum Concurrent Connections: " << acceptor_.max_connections << "]" << endl;
         run_accept();
      }


   private: 
      void run_accept() 
      {
         client_connection::pointer new_connection = 
            client_connection::create(acceptor_.get_io_service());

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
            new_connection->run();
         } else {
            cout << "There was an error: " << error << endl;
         }

         run_accept();
      }

      tcp::acceptor acceptor_;
};

int main(int argc, char** argv) {
   boost::optional<string> username = get_env("USER");
   if(username) {
      cout << "Welcome " << *username << " to the 4917 distributed server!" << endl;
   }

   asio::streambuf buffer;
   std::ostream stream(&buffer);
   message_header header;
   header.type = message_header::REQUESTING_TASKS;

   boost::archive::text_oarchive outArchive(stream);
   outArchive << header;

   cout << stream.rdbuf() << endl;

   // parse the program options
   int max_connections;
   string port;
   po::options_description desc("Program options", DESCRIPTION_WIDTH);
   desc.add_options()
      (
         "help,h", 
         "produce help message"
      )
      (
         "max-connections,n", 
         po::value<int>(&max_connections)->default_value(MAX_CONNECTIONS), 
         "the maximum number of client connections to make at any one time"
      )
      (
         "port,p", 
         po::value<string>(&port)->default_value(DEFAULT_PORT), 
         "the port to start the server on"
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

   asio::io_service io_service;
   const short shortPort = (short) atoi(port.c_str());
   accepting_server::pointer server = 
      accepting_server::pointer(new accepting_server(io_service, shortPort));

   asio::signal_set signals(io_service, SIGINT);
   signals.async_wait(boost::bind(&asio::io_service::stop, &io_service));
   io_service.run();

   cout << "[Successfully closed the server]" << endl;
   return EXIT_SUCCESS;
}

/*
void handleClient(void* data) {
   cout << "[Started dealing with another client]" << endl;
   data = NULL;
   ServerState serverState = WAITING_START;

   // Start communicating with the client. Essentially wait for the client to ask you a question
   const size_t readBufLen = 100;
   byte readBuf[readBufLen];
   while (serverState != FINISHED_CONNECTION) {
      ssize_t readLen = 0;
      // For now I expect the first message to fit into one buffer call.
      readLen = recv(NULL, readBuf, readBufLen, 0);
      if(readLen == 0) {
         cout << "The client has shut down on the other end of the line." << endl;
         break;
      }
      if(readLen > 20) {
         cout << "A client tried to" << endl;
         break;
      }
      char tempStr[5];
      switch(readBuf[0]) {
         case REQUESTING_TASKS:
            sprintf(tempStr, "%d", readBuf[1]);
            cout << "Client is asking for another " << tempStr << " task/s" << endl;
            // TODO Look inside endian.h and pack_processor.h to see how to send this
            // response data over the line.
            break;
         case POSTING_BACK:
            // TODO implement complicated logic.
            // Step 1: Parse into data structure.
            // Step 2: Pass into helper function that does the processing.
            // No need to send anything back to the client. If we don't get it then we
            // will time out eventually.
            break;

         case STATUS_UPDATE:
            // TODO record the status update
            // For the here and now just reset the timeout on that particular client.
            // In the future we will actually display the data usefully on the server.
            break;

         default:
            sprintf(tempStr, "%d", readBuf[0]);
            cout << "Did not understand the incoming data..." << tempStr << endl;
            break;
      }
      // TODO debugging code.
      serverState = FINISHED_CONNECTION;
      // Expect one of two messages "Can I have N tasks?" or "Sorry, quitting"
      // Send the required response or close the connection.
      // Wait for the results to be sent back but do not busy wait so that you can occasionally ping.
      // Recieve the results and update my own data.
   }

   cout << "Closed the client." << endl;
   close(clientData->connectionSocket);
   delete clientData;
}
*/
