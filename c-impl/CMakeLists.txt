cmake_minimum_required(VERSION 3.20)
project(4917_cpp VERSION 1.0.0 LANGUAGES CXX)

option(I4917_BUILD_TESTS "Build CTest unit/property tests" ON)
option(I4917_BUILD_BENCHMARKS "Build standalone C benchmark suite" OFF)
option(I4917_BUILD_GOOGLE_BENCHMARKS "Build optional Google Benchmark comparison suite" OFF)
option(I4917_FETCH_CLI11 "Fetch CLI11 when no installed package is found" ON)
option(I4917_ENABLE_SANITIZERS "Enable AddressSanitizer and UBSan" OFF)
option(I4917_ENABLE_HASKELL_DIFFERENTIAL "Register Haskell differential tests when Stack is available" OFF)

if(I4917_BUILD_TESTS OR I4917_BUILD_BENCHMARKS)
  enable_language(C)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(CLI11 2.7.2 CONFIG QUIET)
if(NOT TARGET CLI11::CLI11)
  if(NOT I4917_FETCH_CLI11 AND NOT FETCHCONTENT_SOURCE_DIR_CLI11)
    message(FATAL_ERROR
      "CLI11 2.7.2 or newer was not found. Install it with your system "
      "package manager, provide FETCHCONTENT_SOURCE_DIR_CLI11, or enable "
      "I4917_FETCH_CLI11.")
  endif()
  include(FetchContent)
  FetchContent_Declare(CLI11
    URL https://github.com/CLIUtils/CLI11/archive/refs/tags/v2.7.2.tar.gz
    URL_HASH SHA256=46eef3101da70852ec7af026e09d485ccee81813331c8c6052d39344443b83da
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(CLI11)
endif()

add_library(4917_core src/machine.cpp)
target_include_directories(4917_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_features(4917_core PUBLIC cxx_std_17)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  target_compile_options(4917_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

add_executable(4917-cpp src/main.cpp)
target_link_libraries(4917-cpp PRIVATE 4917_core CLI11::CLI11)

# Apple GPU search backend. It runs bounded batches on Metal and sends every
# candidate that did not halt within the batch budget to the exact CPU runner.
if(APPLE)
  enable_language(OBJCXX)
  add_executable(4917-metal-search src/metal_search.mm)
  target_link_libraries(4917-metal-search PRIVATE 4917_core
    "-framework Foundation" "-framework Metal")
  target_compile_features(4917-metal-search PRIVATE cxx_std_17)
  set_target_properties(4917-metal-search PROPERTIES
    OBJCXX_STANDARD 17 OBJCXX_STANDARD_REQUIRED YES)
  if(CMAKE_OBJCXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(4917-metal-search PRIVATE -Wall -Wextra -Wpedantic)
  endif()
endif()

if(I4917_BUILD_TESTS)
  enable_testing()
  # The C test consumer exercises the stable C ABI exported by the C++ core.
  add_executable(4917-tests tests/test_machine.c)
  target_link_libraries(4917-tests PRIVATE 4917_core)
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(4917-tests PRIVATE -UNDEBUG)
  endif()
  add_test(NAME machine-properties COMMAND 4917-tests)
  add_executable(4917-search-aggregate-tests tests/test_search_aggregate.cpp)
  target_include_directories(4917-search-aggregate-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_link_libraries(4917-search-aggregate-tests PRIVATE 4917_core)
  add_test(NAME search-aggregate-equivalence COMMAND 4917-search-aggregate-tests)
  add_test(NAME cli-run-json COMMAND 4917-cpp run --program 3,8,15,0 --max-steps 8 --json)
  set_tests_properties(cli-run-json PROPERTIES PASS_REGULAR_EXPRESSION "4917-run-v1.*halted")
  add_test(NAME cli-rejects-invalid-nibble COMMAND 4917-cpp run --program 0,16 --json)
  set_tests_properties(cli-rejects-invalid-nibble PROPERTIES WILL_FAIL TRUE)
  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_Interpreter_FOUND)
    add_test(NAME cli-contract COMMAND ${Python3_EXECUTABLE}
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_cli.py --binary $<TARGET_FILE:4917-cpp>)
    if(APPLE)
      add_test(NAME metal-search-differential COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_metal_search.py
        --metal $<TARGET_FILE:4917-metal-search> --cpu $<TARGET_FILE:4917-cpp>)
    endif()
  endif()
  if(I4917_ENABLE_HASKELL_DIFFERENTIAL AND Python3_Interpreter_FOUND)
    find_program(STACK_EXECUTABLE stack)
    if(STACK_EXECUTABLE)
      add_test(NAME haskell-differential COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/differential.py
        --c $<TARGET_FILE:4917-cpp> --stack ${STACK_EXECUTABLE} --haskell-dir ${CMAKE_CURRENT_SOURCE_DIR}/../haskell-impl)
    endif()
  endif()
endif()

if(I4917_BUILD_BENCHMARKS)
  add_executable(4917-bench benchmarks/bench.c)
  target_link_libraries(4917-bench PRIVATE 4917_core)
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(4917-bench PRIVATE -O3 -Wall -Wextra -Wpedantic)
  endif()
endif()

if(I4917_BUILD_GOOGLE_BENCHMARKS)
  find_package(benchmark 1.9.1 CONFIG REQUIRED)
  add_executable(4917-google-bench benchmarks/google_bench.cpp)
  target_link_libraries(4917-google-bench PRIVATE 4917_core benchmark::benchmark)
  target_compile_definitions(4917-google-bench PRIVATE
    I4917_BENCH_BUILD_TYPE="${CMAKE_BUILD_TYPE}"
    I4917_BENCH_FRAMEWORK_VERSION="${benchmark_VERSION}"
    I4917_BENCH_C_COMPILER="${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}"
    I4917_BENCH_C_FLAGS="${CMAKE_C_FLAGS} ${CMAKE_C_FLAGS_RELEASE}"
    I4917_BENCH_CXX_COMPILER="${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}"
    I4917_BENCH_CXX_FLAGS="${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_RELEASE} -O3")
  execute_process(
    COMMAND git rev-parse --short HEAD
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    OUTPUT_VARIABLE I4917_SOURCE_REVISION
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
  if(NOT I4917_SOURCE_REVISION)
    set(I4917_SOURCE_REVISION "unknown")
  endif()
  target_compile_definitions(4917-google-bench PRIVATE
    I4917_SOURCE_REVISION="${I4917_SOURCE_REVISION}")
  if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(4917-google-bench PRIVATE -O3 -Wall -Wextra -Wpedantic)
  endif()
endif()

if(I4917_ENABLE_SANITIZERS AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  foreach(target 4917_core 4917-cpp 4917-metal-search 4917-tests
                 4917-search-aggregate-tests 4917-bench 4917-google-bench)
    if(TARGET ${target})
      target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
      if(NOT target STREQUAL "4917_core")
        target_link_options(${target} PRIVATE -fsanitize=address,undefined)
      endif()
    endif()
  endforeach()
endif()
