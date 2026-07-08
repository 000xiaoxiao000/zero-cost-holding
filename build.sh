#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

usage() {
  echo "Usage: ./build.sh <platform> <mode> [options]"
  echo ""
  echo "  platform:  android | ios | all"
  echo "  mode:      debug | release | all"
  echo ""
  echo "Examples:"
  echo "  ./build.sh android debug"
  echo "  ./build.sh android release"
  echo "  ./build.sh ios debug"
  echo "  ./build.sh ios release"
  echo "  ./build.sh all debug"
  echo "  ./build.sh all release"
  echo "  ./build.sh all all"
  echo ""
  echo "Options:"
  echo "  --install   (android only) adb install after build"
}

PLATFORM="${1:-}"
MODE="${2:-}"
INSTALL=false

for arg in "$@"; do
  [[ "${arg}" == "--install" ]] && INSTALL=true
done

if [[ -z "${PLATFORM}" || -z "${MODE}" ]]; then
  usage
  exit 1
fi

run_android_debug() {
  echo "=============================="
  echo "  Android  DEBUG"
  echo "=============================="
  bash build_android_debug.sh
  if ${INSTALL}; then
    VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
    APK="build/app/outputs/apk/debug/ZeroCostHolding-v${VERSION}-debug.apk"
    echo "==> adb install ${APK}"
    adb install -r "${APK}"
  fi
}

run_android_release() {
  echo "=============================="
  echo "  Android  RELEASE"
  echo "=============================="
  bash build_android_release.sh
  if ${INSTALL}; then
    VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
    APK="build/app/outputs/apk/release/ZeroCostHolding-v${VERSION}-release.apk"
    echo "==> adb install ${APK}"
    adb install -r "${APK}"
  fi
}

run_ios_debug() {
  echo "=============================="
  echo "  iOS  DEBUG"
  echo "=============================="
  bash build_ios_debug.sh
}

run_ios_release() {
  echo "=============================="
  echo "  iOS  RELEASE"
  echo "=============================="
  bash build_ios_release.sh
}

case "${PLATFORM}:${MODE}" in
  android:debug)   run_android_debug ;;
  android:release) run_android_release ;;
  android:all)     run_android_debug; run_android_release ;;
  ios:debug)       run_ios_debug ;;
  ios:release)     run_ios_release ;;
  ios:all)         run_ios_debug; run_ios_release ;;
  all:debug)       run_android_debug; run_ios_debug ;;
  all:release)     run_android_release; run_ios_release ;;
  all:all)         run_android_debug; run_android_release; run_ios_debug; run_ios_release ;;
  *)
    echo "Error: unknown platform/mode combination '${PLATFORM}/${MODE}'"
    echo ""
    usage
    exit 1
    ;;
esac

echo ""
echo "Done."
