#ifndef __4917_SERVER_CONNECTION
#define __4917_SERVER_CONNECTION

#include "connection.h"
#include "message.h"

class server_connection
{
   public:
      server_connection(boost::asio::io_service& io_service,
                        boost::asio::ip::tcp::resolver::iterator endpoint_iterator)
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
      void handle_connect(const boost::system::error_code& error);
      void wait_for_server(); 
      void requestTasks();
      void handle_message_task_response(const boost::system::error_code& error, message_task_response* mtr);
      void perform_task(uint32_t task);
      void handle_request(const boost::system::error_code& error);

      // The underlying socket that we use for communication.
      connection connection_;
      boost::asio::io_service& io_service_;
      message_header header;
      message_queue outbound_queue;
      boost::asio::strand sender_strand; // is this required?
};

#endif
