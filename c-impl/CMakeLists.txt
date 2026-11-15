cmake_minimum_required(VERSION 3.20)
project(4917_c VERSION 1.0.0 LANGUAGES C)

option(I4917_BUILD_TESTS "Build CTest unit/property tests" ON)
option(I4917_BUILD_BENCHMARKS "Build standalone benchmark suite" OFF)
option(I4917_BUILD_GOOGLE_BENCHMARKS "Build optional Google Benchmark comparison suite" OFF)
option(I4917_FETCH_ARGTABLE3 "Fetch Argtable3 when no system package is installed" ON)
option(I4917_ENABLE_SANITIZERS "Enable AddressSanitizer and UBSan" OFF)
option(I4917_ENABLE_HASKELL_DIFFERENTIAL "Register Haskell differential tests when Stack is available" OFF)

add_library(4917_core src/machine.c)
target_include_directories(4917_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_features(4917_core PUBLIC c_std_11)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  target_compile_options(4917_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

find_package(Argtable3 3.3.1 CONFIG QUIET)
if(NOT TARGET argtable3::argtable3)
  if(NOT I4917_FETCH_ARGTABLE3 AND NOT FETCHCONTENT_SOURCE_DIR_ARGTABLE3)
    message(FATAL_ERROR
      "Argtable3 3.3.1 or newer was not found. Install it with your system "
      "package manager, provide FETCHCONTENT_SOURCE_DIR_ARGTABLE3, or enable "
      "I4917_FETCH_ARGTABLE3.")
  endif()
  include(FetchContent)
  set(ARGTABLE3_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
  set(ARGTABLE3_ENABLE_EXAMPLES OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(argtable3
    URL https://github.com/argtable/argtable3/releases/download/v3.3.1/argtable-v3.3.1.tar.gz
    URL_HASH SHA256=c08bca4b88ddb9234726b75455b3b1670d7c864d8daf198eaa7a3b4d41addf2c
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(argtable3)
endif()

add_executable(4917-c src/main.c)
target_link_libraries(4917-c PRIVATE 4917_core argtable3::argtable3)

if(I4917_ENABLE_SANITIZERS AND CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  foreach(target 4917_core 4917-c)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endforeach()
endif()

if(I4917_BUILD_TESTS)
  enable_testing()
  add_executable(4917-tests tests/test_machine.c)
  target_link_libraries(4917-tests PRIVATE 4917_core)
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    # Assertions are the test harness checks and must remain enabled in Release.
    target_compile_options(4917-tests PRIVATE -UNDEBUG)
  endif()
  if(I4917_ENABLE_SANITIZERS AND CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(4917-tests PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(4917-tests PRIVATE -fsanitize=address,undefined)
  endif()
  add_test(NAME machine-properties COMMAND 4917-tests)
  add_test(NAME cli-run-json COMMAND 4917-c run --program 3,8,15,0 --max-steps 8 --json)
  set_tests_properties(cli-run-json PROPERTIES PASS_REGULAR_EXPRESSION "4917-run-v1.*halted")
  add_test(NAME cli-rejects-invalid-nibble COMMAND 4917-c run --program 0,16 --json)
  set_tests_properties(cli-rejects-invalid-nibble PROPERTIES WILL_FAIL TRUE)
  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_Interpreter_FOUND)
    add_test(NAME cli-contract COMMAND ${Python3_EXECUTABLE}
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_cli.py --binary $<TARGET_FILE:4917-c>)
  endif()
  if(I4917_ENABLE_HASKELL_DIFFERENTIAL AND Python3_Interpreter_FOUND)
    find_program(STACK_EXECUTABLE stack)
    if(STACK_EXECUTABLE)
      add_test(NAME haskell-differential COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/differential.py
        --c $<TARGET_FILE:4917-c> --stack ${STACK_EXECUTABLE} --haskell-dir ${CMAKE_CURRENT_SOURCE_DIR}/../haskell-impl)
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
  # The optional comparison harness is the only C++ target. Production targets
  # and the core library above remain C11 and have no benchmark dependency.
  enable_language(CXX)
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
  set(CMAKE_CXX_EXTENSIONS OFF)

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
