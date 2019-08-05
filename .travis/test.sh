#!/usr/bin/env bash
echo "Starting to test Flutter libraries"
cd $TRAVIS_BUILD_DIR
flutter packages get
echo "Analyzing Flutter library"
flutter analyze --no-pub
echo "Testing Flutter library"
flutter test
