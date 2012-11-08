#!/bin/bash -e

baseDir=${1:-.}

echo "== Finding files to index =="
find "$baseDir"                        \
   -path "$baseDir/gtest*" -prune -o   \
   \(                                  \
      -name "*.cpp" -print -o                 \
      -name "*.hpp" -print -o                 \
      -name "*.h" -print                      \
   \) -a                               \
   -type f                           \
   | tee "${baseDir}/cscope.files"
echo ""

cd "$baseDir"
echo "== Generating CScope Database =="
cscope -b -q -k -v
