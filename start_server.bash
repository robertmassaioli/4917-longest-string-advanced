#!/bin/bash -e

port=${1:-9999}
build_dir=${2:-localbuild}
screen_name="longest-string-server"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$DIR/${build_dir}"
echo "Recompiling the code in:"
echo "   $PWD"
make

if screen -ls | grep "$screen_name" > /dev/null
then
   echo "There was a previous server running, shutting it down and restarting."
   kill `screen -ls | grep longest-string | cut -d. -f1 | tr -d '[:space:]'`
fi

echo "== Starting server on port: ${port} =="
screen -d -m -S "$screen_name" "./server/server" "--port=${port}"

echo ""
echo "Watch: screen -r \"${screen_name}\""
