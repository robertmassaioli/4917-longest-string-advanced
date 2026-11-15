cmake_minimum_required(VERSION 3.20)
project(4917_c VERSION 1.0.0 LANGUAGES C)

option(I4917_BUILD_TESTS "Build CTest unit/property tests" ON)
option(I4917_BUILD_BENCHMARKS "Build standalone benchmark suite" OFF)
option(I4917_BUILD_GOOGLE_BENCHMARKS "Build optional Google Benchmark comparison suite" OFF)
option(I4917_FETCH_GOOGLE_BENCHMARK "Fetch pinned Google Benchmark when no package is installed" ON)
option(I4917_ENABLE_SANITIZERS "Enable AddressSanitizer and UBSan" OFF)
option(I4917_ENABLE_HASKELL_DIFFERENTIAL "Register Haskell differential tests when Stack is available" OFF)

add_library(4917_core src/machine.c)
target_include_directories(4917_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_features(4917_core PUBLIC c_std_11)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  target_compile_options(4917_core PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

# Argtable3 is vendored at a fixed upstream revision so ordinary and offline
# builds never fetch dependencies. Keep it private to the CLI executable.
add_library(4917_argtable3 STATIC
  third_party/argtable3/arg_cmd.c
  third_party/argtable3/arg_date.c
  third_party/argtable3/arg_dbl.c
  third_party/argtable3/arg_dstr.c
  third_party/argtable3/arg_end.c
  third_party/argtable3/arg_file.c
  third_party/argtable3/arg_getopt_long.c
  third_party/argtable3/arg_hashtable.c
  third_party/argtable3/arg_int.c
  third_party/argtable3/arg_lit.c
  third_party/argtable3/arg_rem.c
  third_party/argtable3/arg_rex.c
  third_party/argtable3/arg_str.c
  third_party/argtable3/arg_utils.c
  third_party/argtable3/argtable3.c
)
target_include_directories(4917_argtable3 PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/argtable3)
target_compile_definitions(4917_argtable3 PRIVATE ARG_REPLACE_GETOPT=1)
target_compile_features(4917_argtable3 PRIVATE c_std_11)

add_executable(4917-c src/main.c)
target_link_libraries(4917-c PRIVATE 4917_core 4917_argtable3)

if(I4917_ENABLE_SANITIZERS AND CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  foreach(target 4917_core 4917_argtable3 4917-c)
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

  find_package(benchmark 1.9.1 EXACT CONFIG QUIET)
  if(NOT TARGET benchmark::benchmark)
    if(NOT I4917_FETCH_GOOGLE_BENCHMARK AND
       NOT FETCHCONTENT_SOURCE_DIR_GOOGLEBENCHMARK)
      message(FATAL_ERROR
        "Google Benchmark 1.9.1 was not found. Install its CMake package, "
        "provide FETCHCONTENT_SOURCE_DIR_GOOGLEBENCHMARK, or enable "
        "I4917_FETCH_GOOGLE_BENCHMARK.")
    endif()
    include(FetchContent)
    set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
    set(BENCHMARK_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
    set(BENCHMARK_ENABLE_GTEST_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(googlebenchmark
      URL https://github.com/google/benchmark/archive/c58e6d0710581e3a08d65c349664128a8d9a2461.tar.gz
      URL_HASH SHA256=17fbd9d8ea361688f3059bd381afe828a55479cf3ce77f96b351f30b4a481bc8
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_MakeAvailable(googlebenchmark)
  endif()

  add_executable(4917-google-bench benchmarks/google_bench.cpp)
  target_link_libraries(4917-google-bench PRIVATE 4917_core benchmark::benchmark)
  target_compile_definitions(4917-google-bench PRIVATE
    I4917_BENCH_BUILD_TYPE="${CMAKE_BUILD_TYPE}"
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
