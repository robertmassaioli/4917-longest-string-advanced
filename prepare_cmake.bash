#!/bin/bash -e

echo "Preparing the build to be run."

BUILD_DIR=localbuild

rm -rf $BUILD_DIR
mkdir $BUILD_DIR
cd $BUILD_DIR
cmake .. 

echo "Run: make -C localbuild"
