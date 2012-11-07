#ifndef __4917_MESSAGE
#define __4917_MESSAGE

#include <queue>
#include <vector>

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


class message_container : public serial
{
   private:
      serial *header, *body;

   public:
      message_container(serial* header, serial* body) 
      {
         this->header = header;
         this->body = body;
      };

      serial* getHeader() {
         return header;
      }

      serial* getBody() {
         return body;
      }

      template<class Archive>
      void serialize(Archive& ar, const unsigned int version) {
         ar & *header;
         ar & *body;
      }
};

// TODO add in doxygen documentation so that you can document the code well for the
// future.
class message_queue
{
   private:
      std::queue<message_container*> queue;

   public:
      message_queue() {
         // init the queue and take in all of the objects that you are going to need to
         // manage the messages. I am not sure which way we currently want to 
      }

      bool add(message_container* message) {
         queue.push(message);
         return true;
      }

      message_container* getNext() {
         return queue.front();
      }

      void pop() {
         queue.pop();
      }
};

#endif
