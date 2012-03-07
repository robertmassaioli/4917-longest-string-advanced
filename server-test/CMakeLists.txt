include_directories(${LS_SOURCE_DIR}/common)
include_directories(${LS_SOURCE_DIR}/server)
include_directories(${GTEST_INCLUDE_DIRS})
link_directories(${LS_BINARY_DIR}/common)
link_directories(${LS_BINARY_DIR}/server)

add_executable(server-test main.cpp)
target_link_libraries(server-test taskgenerator ${GTEST_BOTH_LIBRARIES})
