#include "common.h"

boost::optional<std::string> get_env(std::string const &name) 
{ 
   char *var = getenv(name.c_str()); 
   
   if(var) return boost::optional<std::string>(var);
   return boost::none; 
} 
