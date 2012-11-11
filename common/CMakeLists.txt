add_library(processor processor.cpp)
add_library(common common.cpp)
add_library(packer processor_packer.cpp)

add_library(boosthelpers boost_helpers.cpp)
target_link_libraries(boosthelpers
   ${Boost_LIBRARIES}
   )

add_library(clientresults client_results.cpp)
target_link_libraries(clientresults
   packer
   processor
   )
