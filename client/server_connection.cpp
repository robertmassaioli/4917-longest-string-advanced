#include <iostream>

#include "server_connection.h"
#include "client_results.h"
#include "processor.h"
#include "solve_task.h"

#include <boost/smart_ptr/shared_ptr.hpp>
#include <boost/smart_ptr/make_shared.hpp>

using namespace std;
namespace asio = boost::asio;
using boost::asio::ip::tcp;

void server_connection::handle_connect(const boost::system::error_code& error) 
{
   cout << "We made a connection to the server! Success!" << endl;
   // Start waiting for the server to tell us stuff.
   wait_for_server();
   // Request some tasks.
   requestTasks();
}

void server_connection::wait_for_server() 
{
   cout << "Started waiting for the server to tell me something." << endl;
   connection_.async_read(header, 
         boost::bind(
            &server_connection::handle_request,
            this,
            boost::asio::placeholders::error
            ));
}

void server_connection::requestTasks() 
{
   message_header tempHeader;
   tempHeader.type = message_header::REQUESTING_TASKS;
   // TODO configure how many tasks will be requested somewhere.
   message_task_request mtr(2);
   boost::shared_ptr<message_container> mc(new message_container(&tempHeader, &mtr));
   outbound_queue.add(mc);
}

void server_connection::handle_message_task_response(const boost::system::error_code& error, message_task_response* mtr) 
{
   if(error)
   {
      cout << "There was a problem reading the message_task_response." << endl;
   } 
   else
   {
      boost::recursive_mutex::scoped_lock lock(request_mutex);
      cout << "Successfully read the message task response." << endl;

      int tasks = mtr->getTasks().size();
      tasksRemaining += tasks;
      cout << "The server gave us " << tasks << " tasks to perform:" << endl;
      for(int i = 0; i < tasks; ++i) 
      {
         uint32_t currentTask = mtr->getTasks()[i];
         cout << " - " << currentTask << endl;
         // post each of the tasks
         io_service_.post(
               boost::bind(
                  &server_connection::perform_task,
                  this,
                  currentTask)
               );

      }

      // once you are done wait for the server again
      wait_for_server();
   }

   // TODO once you are done with the mtr remember to delete it.
   delete mtr;
}

void server_connection::perform_task(uint32_t task) 
{
   cout << "Running task: " << task << endl;

   // Solve the task that you have been given
   boost::shared_ptr<client_results> result = solveTask(task);


   // Change the data in a stupid way; please remove TODO
   /*
   struct device pretendDevice;
   for(int i = 0; i < 16; ++i)
   {
      pretendDevice.memory[i] = 0;
   }
   init_program(&pretendDevice);
   pretendDevice.memory[5] = 1;
   result->addResult(&pretendDevice, 10);
   */

   // Dummy code to print the result to the screen
   for(int i = 1; i <= 16; ++i) 
   {
      cout << "Program Length " << i
           << " | Longest " << result->getLongestProgram(i)
           << " | Characters " << result->getLongestCharactersPrinted(i) << endl;
   }

   // Now send the data back to the client.
   message_header results_header(message_header::POST_BACK_DATA);
   boost::shared_ptr<message_container> mc = boost::make_shared<message_container>(&results_header, result.get());
   outbound_queue.add(mc);

   boost::recursive_mutex::scoped_lock lock(request_mutex);
   tasksRemaining--;
   if(tasksRemaining == 0)
   {
      requestTasks();
   }
}

void server_connection::handle_request(const boost::system::error_code& error)
{
   if(error) 
   {
      cout << "There was a problem reading the header: " << error.message() << endl;
   }
   else 
   {
      cout << "Header Type: " << header.type << endl;
      // Keep in mind that this message is from the server to this client.
      message_task_response* mtr = NULL;
      switch(header.type) {
         case message_header::REQUESTING_TASKS:
            cout << "The server has given us some tasks to perform." << endl;
            // Parse the message body
            mtr = new message_task_response;
            connection_.async_read(*mtr, 
                  boost::bind(
                     &server_connection::handle_message_task_response,
                     this,
                     boost::asio::placeholders::error,
                     mtr
                     ));
            break;

         case message_header::POST_BACK_DATA:
            cerr << "Somebody has made a dunce mistake. You cannot post result data to the client. That makes no sense." << endl;
            break;

         case message_header::STATUS_UPDATE:
            cout << "Server Requested Status Update." << endl;
            wait_for_server();
            // We do not expect any more information. This message only has a body.
            break;

         default:
            cerr 
               << "[ERROR] The server sent us a header with type '" 
               << header.type 
               << "' which we don't know how to deal with. Closing." 
               << endl;
            break;
      }
   }
}
