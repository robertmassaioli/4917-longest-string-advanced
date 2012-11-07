#ifndef __4917_MESSAGE
#define __4917_MESSAGE

#include "connection.h"

#include <sstream>
#include <queue>
#include <vector>
#include <boost/archive/text_oarchive.hpp>
#include <boost/thread.hpp>
#include <boost/bind.hpp>
#include <boost/asio.hpp>

class serial 
{
   public:
      template<class Archive>
      void serialize(Archive& ar, const unsigned int version);
};

class message_header : public serial
{
   public:
      enum message_type
      {
         REQUESTING_TASKS = 1,
         POST_BACK_DATA = 2,
         STATUS_UPDATE = 3
      } type;

      template<class Archive>
      void serialize(Archive& ar, const unsigned int version) 
      {
         ar & type;
      }
};

// The task responses
class message_task_request : public serial
{
   public:
      template<class Archive>
      void serialize(Archive& ar, const unsigned int version)
      {
         ar & tasksRequested_;
      }

   private:
      short tasksRequested_;
};

// TODO Specify these as a set of ranges. Makes it easier and smaller in the long run.
class message_task_response : public serial
{
   public:
      template<class Archive>
      void serialize(Archive& ar, const unsigned int version)
      {
         ar & tasks_;
      }

      std::vector<uint32_t> getTasks() 
      {
         return tasks_;
      }

   private:
      std::vector<uint32_t> tasks_;
};

// post back data
class message_result_request : serial
{
   public:
      template<class Archive>
      void serialize(Archive& ar, const unsigned int version) 
      {
         ar & task_;
         ar & topResults_;
      }

   private:
      uint32_t task_;
      std::vector<uint32_t> topResults_;
};


class message_container
{
   private:
      std::ostringstream data;

   public:
      template<class Header>
      message_container(Header* header) 
      {
         boost::archive::text_oarchive archive(data);
         archive << *header;
      };

      template<class Header, class Body>
      message_container(Header* header, Body* body) 
      {
         boost::archive::text_oarchive archive(data);
         archive << *header;
         archive << *body;
      };

      std::ostringstream* getData() {
         return &data;
      }
};

// TODO add in doxygen documentation so that you can document the code well for the
// future.
class message_queue
{
   private:
      std::queue<message_container*> queue;
      connection* connection_;
      bool sendingMessage; // The sending message object should be locked.
      boost::recursive_mutex mutex;

   public:
      message_queue(connection* connection) {
         this->connection_ = connection;
         // init the queue and take in all of the objects that you are going to need to
         // manage the messages. I am not sure which way we currently want to 
      }

      bool add(message_container* message) {
         boost::lock_guard<boost::recursive_mutex> lock(mutex);

         queue.push(message);
         pop_message();
         return true;
      }

      void pop_message() {
         boost::lock_guard<boost::recursive_mutex> lock(mutex);

         if(!sendingMessage && !queue.empty()) 
         {
            message_container* container = queue.front();
            connection_->async_write_archive(*(container->getData()),
                  boost::bind(
                     &message_queue::empty_queue,
                     this,
                     boost::asio::placeholders::error
                     ));
            sendingMessage = true;
            delete container;
            queue.pop();
         }
      }

      void empty_queue(const boost::system::error_code& ec) {
         boost::lock_guard<boost::recursive_mutex> lock(mutex);

         sendingMessage = false; // Setting this to false should be the first thing you do.
         if(ec) {
            std::cout << "The message queue had a problem sending a message. It is not sending any more now." << std::endl;
         } else {
            pop_message();
         }
      }
};

#endif
