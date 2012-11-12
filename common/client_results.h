#ifndef __4917_CLIENT_RESULTS
#define __4917_CLIENT_RESULTS

#include <stdint.h>

class run_result
{
   public:
      uint64_t trial;
      int charactersPrinted;

      template<class Archive>
      void serialize(Archive& ar, const unsigned int version) 
      {
         ar & trial;
         ar & charactersPrinted;
      }
};

class client_results
{
   public:
      client_results(uint32_t task);
      void addResult(struct device* program, int charactersPrinted);

      void merge(client_results* other);
      uint32_t getTask();
      uint64_t getLongestProgram(int programLength);
      int getLongestCharactersPrinted(int programLength);

      template<class Archive>
      void serialize(Archive& ar, const unsigned int version) 
      {
         ar & task;
         ar & results;
      }

   private:
      uint32_t task;
      run_result results[16];
};

#endif
