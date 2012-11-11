#!/bin/bash -e

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIR="$SCRIPTS_DIR/.."

cd "$DIR/localbuild"
echo "Recompiling the code in:"
echo "   $PWD"
make

echo ""
echo ""
host=${1:-localhost}
port=${2:-9999}
echo "== Starting Client =="
echo "== Connecting to ${host}:${port} =="
./client/client "$host" "$port"
