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

#include <boost/ref.hpp>
#include <boost/asio.hpp>
#include <boost/optional.hpp>
#include <boost/smart_ptr.hpp>
#include <boost/make_shared.hpp>
#include <boost/program_options.hpp>
#include <boost/thread/thread.hpp>
#include <boost/thread/mutex.hpp>

using namespace std;
using boost::asio::ip::tcp;
namespace po = boost::program_options;
namespace asio = boost::asio;
namespace ip = boost::asio::ip;

typedef unsigned char byte;

enum ClientToServer {
   REQUESTING_TASKS,
   POSTING_BACK,
   STATUS_UPDATE
};

void acceptConnections(void* data);
void handleClient(void* data);
void closeServer(int value);

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

static boost::mutex runningLock;
static bool stopRunning;

static boost::thread_group clientPool;

class ClientThreadData {
   public:
      int connectionSocket;
};

#define MAX_CONNECTIONS    100
#define DEFAULT_PORT       "9999"

class client_connection {
   public:
      static boost::shared_ptr<client_connection> create(asio::io_service& io_service) {
         return boost::shared_ptr<client_connection>(new client_connection(io_service));
      }

      tcp::socket& socket() {
         return socket_;
      }

      void run() {
         // This essentially runs the client and attempts to keep it in contact with the target
         // machine. In here is where we do all of the complicated messaging and handling.
         cout << "Running a client" << endl;
      }

   private:
      client_connection(asio::io_service& io_service)
         : socket_(io_service) 
      {
      }

      ip::tcp::socket socket_;
      // TODO data structure representing last ping
      // list of the current tasks that it has been assigned so that we can reap them when the
      // client disconnects.
};

class accepting_server {
   public:
      accepting_server(asio::io_service& io_service, short port) 
         : acceptor_(io_service, tcp::endpoint(tcp::v6(), port))
      {
         run_accept();
      }


   private: 
      void run_accept() 
      {
         boost::shared_ptr<client_connection> new_connection = 
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
      cout << "Max connections set to: " << max_connections << endl;
   }

   //signal(SIGTERM, closeServer);
   signal(SIGINT, closeServer);

   runningLock.lock();
   stopRunning = false;
   runningLock.unlock();

   asio::io_service io_service;
   ip::tcp::endpoint endpoint(ip::tcp::v6(), atoi(port.c_str()));
   boost::shared_ptr<ip::tcp::acceptor> acceptor = 
      boost::make_shared<ip::tcp::acceptor>(
            boost::ref(io_service)
         );

   boost::system::error_code ec;
   acceptor->open(endpoint.protocol(), ec);
   if(ec) {
      cout << ec << endl;
      return 1;
   }
   acceptor->bind(endpoint, ec);
   if(ec) {
      cout << ec << endl;
      return 2;
   }
   acceptor->listen(asio::socket_base::max_connections, ec);
   if(ec) {
      cout << ec << endl;
      return 3;
   }

   cout << "[Starting the server on port " << port << "]" << endl;

   void* value = NULL;
   boost::thread* acceptThread = new boost::thread(acceptConnections, value);
   acceptThread->join();
   delete acceptThread;
   clientPool.join_all();

   cout << "[Successfully closed the server]" << endl;
   return EXIT_SUCCESS;
}

/**
 * This function is completely in charge of accepting new connections in the server and passing them
 * on to be dealt with.
 */
void acceptConnections(void* data) {
   // Grab the accept data
   cout << "[Started accepting connections from clients]" << endl;
   cout << "[Please press Ctrl-C or send SIG_TERM to shutdown gracefully.]" << endl;
   
   // Setup the shouldLoop variable
   runningLock.lock();
   bool shouldLoop = !stopRunning;
   runningLock.unlock();

   const int timeout = 1000;
   char tmpStr[200];
   while(shouldLoop) {

      runningLock.lock();
      shouldLoop = !stopRunning;
      runningLock.unlock();
   }
   cout << "[Finished accepting connections from clients]" << endl;
}

enum ServerState { WAITING_START, TASK_SENT, FINISHED_CONNECTION };

void handleClient(void* data) {
   cout << "[Started dealing with another client]" << endl;
   ClientThreadData* clientData = (ClientThreadData*) data;
   data = NULL;
   ServerState serverState = WAITING_START;

   // Start communicating with the client. Essentially wait for the client to ask you a question
   const size_t readBufLen = 100;
   byte readBuf[readBufLen];
   while (serverState != FINISHED_CONNECTION) {
      ssize_t readLen = 0;
      // For now I expect the first message to fit into one buffer call.
      readLen = recv(clientData->connectionSocket, readBuf, readBufLen, 0);
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

void closeServer(int value) {
   cout << "Shutting down the server now." << endl;
   runningLock.lock();
   stopRunning = true;
   runningLock.unlock();
}
