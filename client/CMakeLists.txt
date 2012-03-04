include_directories(${LS_SOURCE_DIR}/common)
link_directories(${LS_BINARY_DIR}/common)

add_executable(client main.cpp)
target_link_libraries(client processor)
