add_library(processor SHARED processor.cpp)
add_library(packer SHARED processor_packer.cpp)

add_library(solvetask SHARED solve_task.cpp)
target_link_libraries(solvetask
   processor
   packer
   )

add_library(boosthelpers SHARED boost_helpers.cpp)
target_link_libraries(boosthelpers
   ${Boost_LIBRARIES}
   )

add_library(clientresults SHARED client_results.cpp)
target_link_libraries(clientresults
   packer
   processor
   )
