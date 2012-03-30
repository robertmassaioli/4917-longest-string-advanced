add_library(processor processor.cpp)
add_library(common common.cpp)
add_library(packer SHARED processor_packer.cpp)
