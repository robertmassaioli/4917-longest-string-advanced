#!/bin/bash -e

./generate_cscope.bash
cscope -b -q -k
./prepare_cmake.bash
make -C localbuild
./start_server.bash
./spawn_client.bash
