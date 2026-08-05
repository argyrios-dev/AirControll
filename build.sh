#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "AirControll must be built on macOS 13 or later." >&2
  exit 1
fi

for tool in swift swiftc plutil codesign sips; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

[[ -x /usr/libexec/PlistBuddy ]] || {
  echo "Missing PlistBuddy." >&2
  exit 1
}

SWIFT_MAJOR="$(
  swiftc --version |
  sed -nE 's/.*Swift version ([0-9]+).*/\1/p' |
  head -1
)"

[[ -n "$SWIFT_MAJOR" && "$SWIFT_MAJOR" -ge 6 ]] || {
  echo "Swift 6 or later is required." >&2
  exit 1
}

VERSION="0.1.5"
APP_NAME="AirControll"

APP_BUNDLE="$ROOT/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

SOURCE_ICON="$ROOT/Assets/AirControllIcon.icns"
DESTINATION_ICON="$RESOURCES/AirControllIcon.icns"

is_valid_icns() {
  local path="$1"

  [[ -f "$path" && -s "$path" ]] || return 1

  sips -g format "$path" 2>/dev/null |
    grep -qi 'format: icns'
}

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Application icon not found:" >&2
  echo "$SOURCE_ICON" >&2
  echo "Place a ready-made ICNS file at that exact path." >&2
  exit 1
fi

if ! is_valid_icns "$SOURCE_ICON"; then
  echo "Invalid ICNS application icon:" >&2
  echo "$SOURCE_ICON" >&2
  exit 1
fi

if [[ -x "$ROOT/scripts/validate-repository.sh" ]]; then
  "$ROOT/scripts/validate-repository.sh"
fi

echo "Building for production..."

rm -rf "$APP_BUNDLE"

swift build \
  -c release \
  --product "$APP_NAME"

BIN_PATH="$(
  swift build \
    -c release \
    --show-bin-path
)"

EXECUTABLE="$BIN_PATH/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Release executable was not produced:" >&2
  echo "$EXECUTABLE" >&2
  exit 1
fi

mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

install \
  -m 755 \
  "$EXECUTABLE" \
  "$MACOS/$APP_NAME"

install \
  -m 644 \
  "$ROOT/Info.plist" \
  "$CONTENTS/Info.plist"

install \
  -m 644 \
  "$SOURCE_ICON" \
  "$DESTINATION_ICON"

if [[ -f "$ROOT/Resources/PrivacyInfo.xcprivacy" ]]; then
  install \
    -m 644 \
    "$ROOT/Resources/PrivacyInfo.xcprivacy" \
    "$RESOURCES/PrivacyInfo.xcprivacy"
fi

printf 'APPL????' > "$CONTENTS/PkgInfo"

plutil -lint "$CONTENTS/Info.plist" >/dev/null

if [[ -f "$RESOURCES/PrivacyInfo.xcprivacy" ]]; then
  plutil -lint \
    "$RESOURCES/PrivacyInfo.xcprivacy" \
    >/dev/null
fi

BUNDLE_VERSION="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$CONTENTS/Info.plist"
)"

MINIMUM_SYSTEM="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :LSMinimumSystemVersion' \
    "$CONTENTS/Info.plist"
)"

BUNDLE_EXECUTABLE="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleExecutable' \
    "$CONTENTS/Info.plist"
)"

BUNDLE_ICON="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIconFile' \
    "$CONTENTS/Info.plist"
)"

[[ "$BUNDLE_VERSION" == "$VERSION" ]] || {
  echo "Unexpected bundle version: $BUNDLE_VERSION" >&2
  exit 1
}

[[ "$MINIMUM_SYSTEM" == "13.0" ]] || {
  echo "Unexpected minimum macOS version: $MINIMUM_SYSTEM" >&2
  exit 1
}

[[ "$BUNDLE_EXECUTABLE" == "$APP_NAME" ]] || {
  echo "Unexpected executable name: $BUNDLE_EXECUTABLE" >&2
  exit 1
}

[[ "$BUNDLE_ICON" == "AirControllIcon.icns" ]] || {
  echo "Unexpected icon name in Info.plist: $BUNDLE_ICON" >&2
  exit 1
}

[[ -x "$MACOS/$APP_NAME" ]] || {
  echo "Application executable is missing." >&2
  exit 1
}

is_valid_icns "$DESTINATION_ICON" || {
  echo "Copied application icon is invalid." >&2
  exit 1
}

touch "$APP_BUNDLE"

codesign \
  --force \
  --deep \
  --sign - \
  --timestamp=none \
  "$APP_BUNDLE"

codesign \
  --verify \
  --deep \
  --strict \
  --verbose=2 \
  "$APP_BUNDLE"

echo
echo "Build completed successfully:"
printf '%s\n' "$APP_BUNDLE"
