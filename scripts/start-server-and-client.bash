#!/bin/bash -e

# This kicks off the server and two clients into screens that we can deal with separately
# This is handy for rapid development.

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$SCRIPTS_DIR/.."
BUILD_DIR="$BASE_DIR/localbuild"
DEFAULT_PORT=9999

${SCRIPTS_DIR}/start_server.bash
sleep 1
screen -d -m \
   -S "longest-string-client-one" \
   "$BUILD_DIR/client/client" localhost $DEFAULT_PORT
screen -d -m \
   -S "longest-string-client-two" \
   "$BUILD_DIR/client/client" localhost $DEFAULT_PORT
