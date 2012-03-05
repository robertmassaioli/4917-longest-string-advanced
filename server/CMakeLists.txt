include_directories(${LS_SOURCE_DIR}/common)
link_directories(${LS_BINARY_DIR}/common)

add_library(taskgenerator task_generator.cpp)

add_executable(server main.cpp)
target_link_libraries(server ${CMAKE_THREAD_LIBS_INIT})
