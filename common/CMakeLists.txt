add_library(processor processor.cpp)
add_library(packer SHARED processor_packer.cpp)
add_library(semaphore SHARED semaphore.cpp)
