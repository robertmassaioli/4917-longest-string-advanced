cmake_minimum_required(VERSION 2.8)
project(LS)

find_package(Threads REQUIRED)
find_package(Boost COMPONENTS thread program_options)

add_subdirectory(gtest)
add_subdirectory(common)
add_subdirectory(client)
add_subdirectory(server)
add_subdirectory(common-test)
#add_subdirectory(client-test)
add_subdirectory(server-test)

enable_testing()
add_test(NAME ServerTests COMMAND server-test/server-test)
add_test(NAME ProcessorTests COMMAND common-test/test_processor)
add_test(NAME PackerTests COMMAND common-test/test_packer)
