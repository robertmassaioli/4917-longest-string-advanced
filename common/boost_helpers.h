#ifndef __4917_BOOST_HELPERS
#define __4917_BOOST_HELPERS

#include <boost/asio.hpp>

/**
 * \brief Runs an asio io_service with multiple threads.
 *
 * This function will run an io_service in multiple threads and will block until the io_service is
 * done.
 * \param io_service The io_service to run in a thread pool.
 * \param thread_count The number of threads to make avaliable in the thread pool.
 */
void run_threaded(boost::asio::io_service& io_service, int thread_count);

#endif
