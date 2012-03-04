#include <iostream>
#include <cstdlib>
#include <cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <pthread.h>

using namespace std;

void* acceptConnections(void* data);

static const char* success = "SUCCESS!";
static const char* failed = "FAILED!";

#define MAX_CONNECTIONS 100

int main(int argc, char** argv) {
   cout << "[Starting the server]" << endl;
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
   int error = getaddrinfo(NULL, argv[1], &hints, &result);
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
         cout << "socket creation " << failed << endl;
         continue;
      }
      if(bind(socketFD, rp->ai_addr, rp->ai_addrlen) == 0) {
         cout << success << endl;
         break;
      }
      cout << "socket bind " << failed << endl;
      close(socketFD);
   }

   if(rp == NULL) {
      cerr << "Did not manage to bind any sockets or ports." << endl;
      exit(EXIT_FAILURE);
   }

   listen(socketFD, MAX_CONNECTIONS);

   pthread_t acceptThread;
   pthread_create(&acceptThread, NULL, acceptConnections, NULL);
   pthread_join(acceptThread, NULL);

   close(socketFD);
   cout << "[Successfully closed the server]" << endl;
   return EXIT_SUCCESS;
}

/**
 * This function is completely in charge of accepting new connections in the server and passing them
 * on to be dealt with.
 */
void* acceptConnections(void* data) {
   cout << "[Started accepting connections from clients]" << endl;
   cout << "[Finished accepting connections from clients]" << endl;
}
