#include <cstring>
#include "common.h"

using namespace std;

boost::optional<string> get_env(string const &name) 
{ 
   char *var = getenv(name.c_str()); 
   
   if(var) return boost::optional<string>(var);
   return boost::none; 
} 
