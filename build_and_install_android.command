#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build_debug_apk.sh

adb install -r build/app/outputs/apk/debug/ZeroCostHolding-v1.0.0-debug.apk

echo
echo "Build and install complete."
