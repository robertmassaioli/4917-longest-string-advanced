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
         STATUS_UPTATE = 3
      } type;

      template<class Archive>
      void serialize(Archive& ar, const unsigned int version) 
      {
         ar & type;
      }
};


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

#endif
