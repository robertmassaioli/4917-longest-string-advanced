// TODO Merge this with boost_helpers.h
#ifndef __RM_COMMON
#define __RM_COMMON

// This file is supposed to contain a whole bunch of common helper functions.
#include <string>
#include <boost/optional.hpp>

boost::optional<std::string> get_env(std::string const &name);

#endif
