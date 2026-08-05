#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for tool in rsync ditto unzip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

./build.sh
./make-dmg.sh --skip-build
ARCHIVE="$ROOT/AirControll-0.1.5.zip"
DMG="$ROOT/AirControll-0.1.5.dmg"
rm -f "$ARCHIVE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rsync -a \
  --exclude '.build' \
  --exclude '.git' \
  --exclude '.swiftpm' \
  --exclude 'AirControll-0.1.5.zip' \
  --exclude 'AirControll-0.1.5.dmg' \
  --exclude 'AirControll.app' \
  "$ROOT/" "$TMP/AirControll/"
cp -R "$ROOT/AirControll.app" "$TMP/AirControll/AirControll.app"

(
  cd "$TMP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent AirControll "$ARCHIVE"
)
unzip -t "$ARCHIVE" >/dev/null
printf '%s\n' "$ARCHIVE"
