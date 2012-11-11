cmake_minimum_required(VERSION 2.8)
project(LS)

enable_testing()
find_package(Threads REQUIRED)
find_package(Boost REQUIRED COMPONENTS 
   thread 
   program_options 
   system 
   regex
   serialization
   )

add_subdirectory(gtest)
add_subdirectory(common)
add_subdirectory(client)
add_subdirectory(server)
add_subdirectory(common-test)
#add_subdirectory(client-test)
add_subdirectory(server-test)

set($ENV{GTEST_COLOR} "yes")


set(TESTFILES 
   "server-test/server-test"
   "common-test/test_processor"
   "common-test/test_packer"
   )

foreach(TESTFILE ${TESTFILES})
   add_test("${TESTFILE}" 
      "${TESTFILE}" 
      "--gtest_output=xml:${TESTFILE}.xml"
      "--gtest_color=yes"
      )
endforeach()
