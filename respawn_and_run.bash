#!/bin/bash -e

./start_server.bash

for i in `seq 1 3`
do
   ./spawn_client.bash
done
