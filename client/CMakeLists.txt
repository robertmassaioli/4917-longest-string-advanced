include_directories(${LS_SOURCE_DIR}/common)
link_directories(${LS_BINARY_DIR}/common)

add_library(task_queue task_queue.cpp)

add_executable(client main.cpp)
target_link_libraries(client 
   ${CMAKE_THREAD_LIBS_INIT}
   ${Boost_LIBRARIES}
   task_queue
   processor 
   )
