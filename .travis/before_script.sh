#!/usr/bin/env bash
set -e
echo "Applying before_script..."
cd ..
git clone https://github.com/flutter/flutter.git
export PATH=`pwd`/flutter/bin:`pwd`/flutter/bin/cache/dart-sdk/bin:$PATH
cd $TRAVIS_BUILD_DIR
