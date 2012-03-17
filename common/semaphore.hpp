#ifndef __4917_SEMAPHORE
#define __4917_SEMAPHORE

#include <boost/thread/condition_variable.hpp>
#include <boost/thread/mutex.hpp>    
#include <boost/thread/locks.hpp>

class Semaphore
{
    //The current semaphore count.
    unsigned int count_;

    //mutex_ protects count_.
    //Any code that reads or writes the count_ data must hold a lock on
    //the mutex.
    boost::mutex mutex_;

    //Code that increments count_ must notify the condition variable.
    boost::condition_variable condition_;

public:
   explicit Semaphore(unsigned int initial_count) 
    : count_(initial_count),
      mutex_(), 
      condition_()
   {
   }

    unsigned int get_count(); //for debugging/testing only
    void signal(); //called "release" in Java
    void wait(); //called "acquire" in Java
};

#endif
