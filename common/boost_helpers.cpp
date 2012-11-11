#include "boost_helpers.h"

#include <boost/smart_ptr.hpp>
#include <boost/thread/thread.hpp>

void run_threaded(boost::asio::io_service& io_service, int thread_count)
{
   // Kick off all of the threads;
   std::vector<boost::shared_ptr<boost::thread> > threads;
   for(std::size_t i = 0; i < thread_count; ++i)
   {
      boost::shared_ptr<boost::thread> thread(
            new boost::thread(
               boost::bind(
                  &boost::asio::io_service::run,
                  &io_service
                  )
               )
            );

      threads.push_back(thread);
   }

   for(std::size_t i = 0; i < threads.size(); ++i)
   {
      threads[i]->join();
   }
}

boost::optional<std::string> get_env(std::string const &name) 
{ 
   char *var = getenv(name.c_str()); 
   
   if(var) return boost::optional<std::string>(var);
   return boost::none; 
} 
