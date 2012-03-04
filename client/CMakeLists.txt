include_directories(${LS_SOURCE_DIR}/common)
link_directories(${LS_BINARY_DIR}/common)

add_executable(longestString main.cpp)
target_link_libraries(longestString processor)
