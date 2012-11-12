include_directories(${LS_SOURCE_DIR}/common ${Boost_INCLUDE_DIRS})
link_directories(${LS_BINARY_DIR}/common)

add_library(taskgenerator SHARED task_generator.cpp)
add_library(taskmanager SHARED task_manager.cpp)

add_library(clientconnection SHARED client_connection.cpp)
target_link_libraries(clientconnection
   ${Boost_LIBRARIES}
   clientresults
   taskmanager
   taskgenerator
   )

add_executable(server server.cpp)
target_link_libraries(server 
   ${CMAKE_THREAD_LIBS_INIT}
   ${Boost_LIBRARIES}
   clientconnection
   boosthelpers
)
