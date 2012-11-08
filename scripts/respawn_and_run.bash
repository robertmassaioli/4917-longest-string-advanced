#!/bin/bash -e

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${SCRIPTS_DIR}/start_server.bash

for i in `seq 1 3`
do
   ${SCRIPTS_DIR}/spawn_client.bash
done
