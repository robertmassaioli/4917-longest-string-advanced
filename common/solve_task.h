/**
 * @file solve_task.h
 * \brief This file contains functions that help us solve tasks.
 *
 * The client function actually needs this to solve tasks and the server may need this at
 * some point in time if it ever wants to spend the cycles verifying a client.
 */

#ifndef __4917_SOLVE_TASK
#define __4917_SOLVE_TASK

#include "client_results.h"
#include <boost/smart_ptr/shared_ptr.hpp>

/**
 * \brief Solves a given task.
 *
 * The entire problem space in this program has been broken down into tasks. This function
 * is capable of accepting a task and giving us back the solutions.
 *
 * \param task The task to solve for.
 * \return The results of running the task.
 */
boost::shared_ptr<client_results> solveTask(uint32_t task);

#endif
