#!/bin/bash -e

# This kicks off the server and two clients into screens that we can deal with separately
# This is handy for rapid development.

BUILD_DIR=localbuild
DEFAULT_PORT=9999

screen -d -m -S "longest-string-server" "$BUILD_DIR/server/server"
sleep 1
screen -d -m \
   -S "longest-string-client-one" \
   "$BUILD_DIR/client/client" localhost $DEFAULT_PORT
screen -d -m \
   -S "longest-string-client-two" \
   "$BUILD_DIR/client/client" localhost $DEFAULT_PORT
