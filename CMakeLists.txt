cmake_minimum_required(VERSION 2.8)
project(LS)

find_package(Threads)

add_subdirectory(common)
add_subdirectory(client)
add_subdirectory(server)
