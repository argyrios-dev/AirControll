#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="AirControll"
VERSION="0.1.5"
APP_PATH="$ROOT/${APP_NAME}.app"
DMG_PATH="$ROOT/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/AirControll-DMG.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

for tool in hdiutil codesign ditto; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "AirControll.app does not exist. Run ./build.sh first." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$STAGING_DIR"

ditto "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"

ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

echo
echo "DMG created successfully:"
printf '%s\n' "$DMG_PATH"
