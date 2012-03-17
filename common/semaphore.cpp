#include "semaphore.hpp"

 unsigned int Semaphore::get_count() //for debugging/testing only
 {
     //The "lock" object locks the mutex when it's constructed,
     //and unlocks it when it's destroyed.
     boost::unique_lock<boost::mutex> lock(mutex_);
     return count_;
 }

 void Semaphore::signal() //called "release" in Java
 {
     boost::unique_lock<boost::mutex> lock(mutex_);

     ++count_;

     //Wake up any waiting threads. 
     //Always do this, even if count_ wasn't 0 on entry. 
     //Otherwise, we might not wake up enough waiting threads if we 
     //get a number of signal() calls in a row.
     condition_.notify_one(); 
 }

 void Semaphore::wait() //called "acquire" in Java
 {
     boost::unique_lock<boost::mutex> lock(mutex_);
     while (count_ == 0)
     {
          condition_.wait(lock);
     }
     --count_;
 }
