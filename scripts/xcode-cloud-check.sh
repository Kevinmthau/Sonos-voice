#!/bin/sh
set -eu

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.derived/XcodeCloudCheck}"

echo "Checking Xcode project and shared scheme..."
xcodebuild -list -json -project SonosVoiceRemote.xcodeproj >/dev/null

echo "Building iOS Release target with local signing disabled..."
xcodebuild build \
  -project SonosVoiceRemote.xcodeproj \
  -scheme SonosVoiceRemote \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO

if [ "${RUN_ARCHIVE_CHECK:-0}" = "1" ]; then
  ARCHIVE_PATH="${ARCHIVE_PATH:-$DERIVED_DATA_PATH/SonosVoiceRemote.xcarchive}"

  echo "Archiving iOS Release target with local signing disabled..."
  xcodebuild archive \
    -project SonosVoiceRemote.xcodeproj \
    -scheme SonosVoiceRemote \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO
fi

echo "Running web tests..."
npm test

echo "Building web app..."
npm run build

echo "Xcode Cloud readiness check passed."
