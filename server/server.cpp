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

#include <boost/optional.hpp>
#include <boost/program_options.hpp>
#include <boost/thread/thread.hpp>
#include <boost/thread/mutex.hpp>

using namespace std;
namespace po = boost::program_options;

typedef unsigned char byte;

void acceptConnections(void* data);
void handleClient(void* data);
void closeServer(int value);

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

static boost::mutex runningLock;
static bool stopRunning;

static boost::thread_group clientPool;

class AcceptThreadData {
   public:
      int listenSocket;
};

class ClientThreadData {
   public:
      int connectionSocket;
};

#define MAX_CONNECTIONS    100
#define DEFAULT_PORT       "9999"

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

   cout << "[Starting the server on port " << port << "]" << endl;
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
   int error = getaddrinfo(NULL, port.c_str(), &hints, &result);
   if(error != 0) {
      cerr << "getaddrinfo: " << gai_strerror(error) << endl;
      exit(EXIT_FAILURE);
   }

   int socketFD = -1;
   struct addrinfo *rp = NULL;
   for(rp = result; rp != NULL; rp = rp->ai_next) {
      cout << "Attempting to connect a socket...";
      socketFD = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
      if(socketFD == -1) {
         perror("Failed to create a socket");
         continue;
      }
      if(bind(socketFD, rp->ai_addr, rp->ai_addrlen) == 0) {
         cout << "socket bind " << success << endl;
         break;
      }
      perror("Failed to bind a socket.");
      close(socketFD);
   }

   if(rp == NULL) {
      cerr << "Did not manage to bind any sockets or ports." << endl;
      exit(EXIT_FAILURE);
   }

   if(listen(socketFD, MAX_CONNECTIONS) != 0) {
      perror("Failed to open a listening socket");
      exit(EXIT_FAILURE);
   }

   AcceptThreadData* acceptData = new AcceptThreadData();
   acceptData->listenSocket = socketFD;
   boost::thread* acceptThread = new boost::thread(acceptConnections, acceptData);
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
   AcceptThreadData* acceptData = (AcceptThreadData*) data;
   data = NULL;
   cout << "[Started accepting connections from clients]" << endl;
   cout << "[Please press Ctrl-C or send SIG_TERM to shutdown gracefully.]" << endl;
   
   // Setup the shouldLoop variable
   runningLock.lock();
   bool shouldLoop = !stopRunning;
   runningLock.unlock();

   const nfds_t fdCount = 1;
   struct pollfd* fds = (struct pollfd*) malloc(sizeof(struct pollfd) * fdCount);
   fds[0].fd = acceptData->listenSocket;
   fds[0].events = POLLIN;

   const int timeout = 1000;
   char tmpStr[200];
   while(shouldLoop) {
      int pollResponse = poll(fds, fdCount, timeout);
      if(pollResponse > 0) {
         struct sockaddr client;
         socklen_t clientAddrLen;
         int newClient = accept(acceptData->listenSocket, &client, &clientAddrLen);
         if(newClient > -1) {
            ClientThreadData* clientData = new ClientThreadData();
            clientData->connectionSocket = newClient;
            boost::thread* clientThread = new boost::thread(handleClient, clientData);
            if(clientThread != NULL) {
               clientPool.add_thread(clientThread);
            }
            const char* res = inet_ntop(client.sa_family, &client, tmpStr, 200);
            if(res != NULL) {
               cout << "Accepted a new socket from: " << res << endl;
            }
         } else {
            perror("Error while attempting to accept socket.");
            cout << "Shutting down server..." << endl;
            runningLock.lock();
            stopRunning = true;
            runningLock.unlock();
         }
      } else if(pollResponse < 0) {
         perror("There was an error with the poller");
      }

      runningLock.lock();
      shouldLoop = !stopRunning;
      runningLock.unlock();
   }
   cout << "[Finished accepting connections from clients]" << endl;
   close(acceptData->listenSocket);
   delete acceptData;
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
         case 1:
            sprintf(tempStr, "%d", readBuf[1]);
            cout << "Client is asking for another " << tempStr << " task/s" << endl;
            // TODO Look inside endian.h and pack_processor.h to see how to send this
            // response data over the line.
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
