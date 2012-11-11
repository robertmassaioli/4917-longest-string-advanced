#!/bin/bash -e

echo "Requirements: rm, mkdir, cd, cmake"
echo "Preparing the build to be run."

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$SCRIPTS_DIR/.."
BUILD_DIR=${1:-${BASE_DIR}/localbuild}

rm -rf $BUILD_DIR
mkdir $BUILD_DIR
cd $BUILD_DIR
cmake .. 

echo ""
echo "Run: make -C localbuild"
