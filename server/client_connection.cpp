#include "client_connection.h"

#include <iostream>

using namespace std;
using boost::asio::ip::tcp;
namespace asio = boost::asio;

void client_connection::run() {
   wait_for_request();
   // This essentially runs the client and attempts to keep it in contact with the target
   // machine. In here is where we do all of the complicated messaging and handling.

   // Kick off a read async task for anything that the client might want to send us
   // Kick off a periodic status update task that the client can return to us
}

tcp::socket& client_connection::socket() {
   return connection_.socket();
}

void client_connection::wait_for_request() 
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

void client_connection::handle_header(const boost::system::error_code& ec)
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

void client_connection::handle_data(const boost::system::error_code& ec)
{
}

void client_connection::handle_write(const boost::system::error_code& ec) 
{
   // do nothing for now
}

void client_connection::handle_task_request(boost::shared_ptr<message_task_request> mt_request, const boost::system::error_code& ec) 
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

void client_connection::handle_results(boost::shared_ptr<client_results> clientResults, const boost::system::error_code& ec) 
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

void client_connection::handle_status_update() 
{
   // The client has given us a status update. Deal with it and save that data.
}
