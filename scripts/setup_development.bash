#!/bin/bash -e

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${SCRIPTS_DIR}/generate_cscope.bash
cscope -b -q -k
${SCRIPTS_DIR}/prepare_cmake.bash
make -C localbuild
${SCRIPTS_DIR}/start_server.bash
${SCRIPTS_DIR}/spawn_client.bash
