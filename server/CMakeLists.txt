include_directories(${LS_SOURCE_DIR}/common ${Boost_INCLUDE_DIRS})
link_directories(${LS_BINARY_DIR}/common)

add_library(taskgenerator task_generator.cpp)

add_executable(server server.cpp)
target_link_libraries(server 
   ${CMAKE_THREAD_LIBS_INIT}
   ${Boost_LIBRARIES}
)
