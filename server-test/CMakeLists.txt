include_directories(${LS_SOURCE_DIR}/common)
include_directories(${LS_SOURCE_DIR}/server)
include_directories(${gtest_SOURCE_DIR}/include ${gtest_SOURCE_DIR})
link_directories(${LS_BINARY_DIR}/common)
link_directories(${LS_BINARY_DIR}/server)

add_executable(server-test main.cpp)
target_link_libraries(server-test taskgenerator gtest gtest_main)
