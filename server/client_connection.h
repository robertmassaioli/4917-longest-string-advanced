#ifndef __4917_CLIENT_CONNECTION
#define __4917_CLIENT_CONNECTION

#include "task_generator.h"
#include "task_manager.h"
#include "message.h"
#include "client_results.h"

#include <boost/smart_ptr.hpp>
#include <boost/asio.hpp>

// TODO the message_queue is not thread safe at all. Make it so that it is.
class client_connection 
   : public boost::enable_shared_from_this<client_connection>
{
   public:
      typedef boost::shared_ptr<client_connection> pointer;

      static pointer create(boost::asio::io_service& io_service, boost::shared_ptr<TaskGenerator> tg) {
         return pointer(new client_connection(io_service, tg));
      }

      boost::asio::ip::tcp::socket& socket(); 
      void run(); 

   private:
      client_connection(boost::asio::io_service& io_service, boost::shared_ptr<TaskGenerator> taskGenerator)
         : connection_(io_service)
         , outbound_queue(&connection_) 
         , taskManager(new task_manager(taskGenerator))
      {
         // WARNING: The client is not connected here. They only connect as of the run function.
      }

      void wait_for_request();

      void handle_header(const boost::system::error_code& ec);

      void handle_data(const boost::system::error_code& ec);

      void handle_write(const boost::system::error_code& ec);

      void handle_task_request(boost::shared_ptr<message_task_request> mt_request, const boost::system::error_code& ec);

      void handle_results(boost::shared_ptr<client_results> clientResults, const boost::system::error_code& ec);

      void handle_status_update();

      // TODO work out why people use this enum trick?
      enum { header_length = 4 };

      connection connection_;
      message_queue outbound_queue;
      message_header header;
      boost::shared_ptr<task_manager> taskManager;
      // TODO data structure representing last ping
      // list of the current tasks that it has been assigned so that we can reap them when the
      // client disconnects.
};

#endif
