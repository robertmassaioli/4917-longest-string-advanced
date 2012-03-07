cmake_minimum_required(VERSION 2.8)
project(LS)

find_package(GTest REQUIRED)
find_package(Threads REQUIRED)

add_subdirectory(common)
add_subdirectory(client)
add_subdirectory(server)
add_subdirectory(common-test)
#add_subdirectory(client-test)
add_subdirectory(server-test)

enable_testing()
add_test(NAME ServerTests COMMAND server-test/server-test)
add_test(NAME ProcessorTests COMMAND common-test/test_processor)
