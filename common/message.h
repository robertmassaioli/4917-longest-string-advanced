#ifndef __4917_MESSAGE
#define __4917_MESSAGE

#include <vector>

class message_header
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
class message_task_request 
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

class message_task_response
{
   public:
      template<class Archive>
      void serialize(Archive& ar, const unsigned int version)
      {
         ar & tasks_;
      }

   private:
      std::vector<uint32_t> tasks_;
};

// post back data
class message_result_request
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

#endif
