#ifndef __4917_BOOST_HELPERS
#define __4917_BOOST_HELPERS

#include <string>

#include <boost/asio.hpp>
#include <boost/optional.hpp>

/**
 * \brief Runs an asio io_service with multiple threads.
 *
 * This function will run an io_service in multiple threads and will block until the io_service is
 * done.
 * \param io_service The io_service to run in a thread pool.
 * \param thread_count The number of threads to make avaliable in the thread pool.
 */
void run_threaded(boost::asio::io_service& io_service, int thread_count);

/**
 * \brief Get the value of an environment variable with the given name.
 *
 * \param name The name of the environment to get the value of.
 * \return The value that was inside the variable or nothing if the variable never existed at all.
 */
boost::optional<std::string> get_env(std::string const &name);

#endif
