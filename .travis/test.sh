#!/usr/bin/env bash
echo "Starting to test Flutter libraries"
cd $TRAVIS_BUILD_DIR
flutter packages get
echo "Analyzing Flutter library $d"
flutter analyze --no-pub
echo "Testing Flutter library $d"
flutter test
