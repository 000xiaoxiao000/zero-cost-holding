#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
OUTPUT="build/ios/iphonesimulator/Runner.app"

echo "==> [iOS Debug] flutter pub get"
flutter pub get

echo "==> [iOS Debug] build ios --debug (simulator)"
flutter build ios --debug --simulator --no-codesign

echo ""
echo "Build complete: ${OUTPUT}"
echo "Run on simulator:  open -a Simulator && xcrun simctl install booted ${OUTPUT}"
