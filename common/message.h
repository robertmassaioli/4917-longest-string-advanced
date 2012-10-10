#ifndef __4917_MESSAGE
#define __4917_MESSAGE

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

#endif
