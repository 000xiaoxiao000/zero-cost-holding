#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build_android_debug.sh

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
adb install -r "build/app/outputs/apk/debug/ZeroCostHolding-v${VERSION}-debug.apk"

echo
echo "Build and install complete."
