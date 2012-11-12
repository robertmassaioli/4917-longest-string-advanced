include_directories(${LS_SOURCE_DIR}/common)
include_directories(${gtest_SOURCE_DIR}/include ${gtest_SOURCE_DIR})
link_directories(${LS_BINARY_DIR}/common)

set(GTEST_LIBS gtest gtest_main)

add_executable(test_processor test_processor.cpp)
target_link_libraries(test_processor 
   ${GTEST_LIBS}
   processor
   )

add_executable(test_packer test_packer.cpp)
target_link_libraries(test_packer 
   ${GTEST_LIBS}
   packer 
   )

add_executable(test_client_results test_client_results.cpp)
target_link_libraries(test_client_results
   ${GTEST_LIBS}
   clientresults
   )
