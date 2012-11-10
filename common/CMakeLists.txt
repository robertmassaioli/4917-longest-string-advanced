add_library(processor processor.cpp)
add_library(common common.cpp)
add_library(packer SHARED processor_packer.cpp)

add_library(clientresults SHARED client_results.cpp)
target_link_libraries(clientresults
   packer
   )
