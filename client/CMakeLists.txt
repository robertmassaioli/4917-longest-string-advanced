include_directories(${LS_SOURCE_DIR}/common)
link_directories(${LS_BINARY_DIR}/common)

add_library(task_queue task_queue.cpp)
add_library(server_connection SHARED server_connection.cpp)
target_link_libraries(server_connection
   solvetask
   clientresults
   )

add_executable(client client.cpp)
target_link_libraries(client 
   ${CMAKE_THREAD_LIBS_INIT}
   ${Boost_LIBRARIES}
   task_queue
   server_connection
   processor 
   clientresults
   boosthelpers
   )
