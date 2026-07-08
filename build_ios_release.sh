#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
IPA_DIR="build/ios/ipa"

echo "==> [iOS Release] flutter pub get"
flutter pub get

echo "==> [iOS Release] build ipa"
# Requires a valid signing identity and provisioning profile configured in Xcode.
# Set TEAM_ID and BUNDLE_ID via environment or edit below.
TEAM_ID="${TEAM_ID:-}"
BUNDLE_ID="${BUNDLE_ID:-com.zerocost.holdingApp}"

if [[ -z "${TEAM_ID}" ]]; then
  echo "WARNING: TEAM_ID is not set. Building without explicit team. Set TEAM_ID=<your-team-id> to sign properly."
  flutter build ipa --release \
    --dart-define=FLUTTER_BUILD_NAME="${VERSION}"
else
  flutter build ipa --release \
    --dart-define=FLUTTER_BUILD_NAME="${VERSION}" \
    --export-options-plist=ios/ExportOptions.plist
fi

echo ""
echo "Build complete. IPA directory: ${IPA_DIR}"
ls -lh "${IPA_DIR}"/*.ipa 2>/dev/null || echo "(No .ipa found — check signing configuration)"
