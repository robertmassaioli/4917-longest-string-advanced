#ifndef __4917_SERVER_CONNECTION
#define __4917_SERVER_CONNECTION

#include "connection.h"
#include "message.h"

/**
 * \brief The class that manages the connection to the server.
 */
class server_connection
{
   public:
      /**
       * The constructor kicks off a connection to the server in the constructor.
       *
       * \param io_service The io_service to use to perform the connections.
       * \param endpoint_iterator The endpoint that points towards where we expect the
       * server to be.
       */
      server_connection(boost::asio::io_service& io_service,
                        boost::asio::ip::tcp::resolver::iterator endpoint_iterator)
         : io_service_(io_service), 
           connection_(io_service), 
           outbound_queue(&connection_)
      {
          boost::asio::async_connect(connection_.socket(), endpoint_iterator,
              boost::bind(&server_connection::handle_connect, this,
                boost::asio::placeholders::error));
      }

   private:
      /**
       * When this function is called we are finally connected to the server.
       * \param error The error if one ocurred while we were attempting to connect.
       */
      void handle_connect(const boost::system::error_code& error);

      /**
       * This function kicks off an async task that waits for the server to tell us
       * something.
       */
      void wait_for_server(); 

      /**
       * This function sends a request to the server for a number of tasks.
       */
      void requestTasks();

      /**
       * Should be called when the server gives us some tasks to deal with.
       *
       * \param error If there was an error parsing the response then we are sent here.
       * \param mtr The message task response.
       */
      void handle_message_task_response(const boost::system::error_code& error, message_task_response* mtr);

      /**
       * Performs a single given task.
       *
       * \param task The task to perform.
       */
      void perform_task(uint32_t task);

      /**
       * Handles any request in general from the server.
       *
       * \param error Provided if there was an error while we tried to read a header from
       * the server.
       */
      void handle_request(const boost::system::error_code& error);

      // The underlying socket that we use for communication.
      connection connection_;
      boost::asio::io_service& io_service_;
      message_header header;
      message_queue outbound_queue;
};

#endif
