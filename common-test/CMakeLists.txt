include_directories(${LS_SOURCE_DIR}/common)
include_directories(${gtest_SOURCE_DIR}/include ${gtest_SOURCE_DIR})
link_directories(${LS_BINARY_DIR}/common)

add_executable(test_processor test_processor.cpp)
target_link_libraries(test_processor processor gtest gtest_main)

add_executable(test_packer test_packer.cpp)
target_link_libraries(test_packer packer gtest gtest_main)
