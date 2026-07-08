#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"

unset http_proxy https_proxy all_proxy no_proxy
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
unset JAVA_TOOL_OPTIONS JDK_JAVA_OPTIONS GRADLE_OPTS JAVA_OPTS

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
OUTPUT="build/app/outputs/apk/release/ZeroCostHolding-v${VERSION}-release.apk"

echo "==> [Android Release] flutter pub get"
flutter pub get

echo "==> [Android Release] assembleRelease"
cd android
./gradlew --no-daemon \
  -Djava.net.useSystemProxies=false \
  assembleRelease

cd ..
echo ""
echo "Build complete: ${OUTPUT}"
