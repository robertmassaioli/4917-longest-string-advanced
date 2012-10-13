#!/bin/bash -e

echo "Preparing the build to be run."

BUILD_DIR=localbuild
GTEST_ROOT="~/Code/C/googletest"

rm -rf $BUILD_DIR
mkdir $BUILD_DIR
cd $BUILD_DIR
cmake .. -DGTEST_ROOT=$GTEST_ROOT || cmake .. -DGTEST_ROOT=$GTEST_ROOT/localbuild

echo "Run: make -C localbuild"
