include_directories(${LS_SOURCE_DIR}/common)
include_directories(${GTEST_INCLUDE_DIRS})
link_directories(${LS_BINARY_DIR}/common)

add_executable(test_processor test_processor.cpp)
target_link_libraries(test_processor processor ${GTEST_BOTH_LIBRARIES})

add_executable(test_packer test_packer.cpp)
target_link_libraries(test_packer packer ${GTEST_BOTH_LIBRARIES})
