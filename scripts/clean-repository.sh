#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Removing generated build and release files..."

rm -rf \
  .build \
  .swiftpm \
  DerivedData \
  AirControll.app \
  .tmp \
  tmp

find "$ROOT" \
  -type d \
  \( -name '__pycache__' -o -name 'xcuserdata' \) \
  -prune \
  -exec rm -rf {} +

find "$ROOT" \
  -type f \
  \( \
    -name '.DS_Store' \
    -o -name '._*' \
    -o -name '*.pyc' \
    -o -name '*.tmp' \
    -o -name '*.temp' \
    -o -name '*.bak' \
    -o -name '*.backup' \
    -o -name '*.orig' \
    -o -name '*~' \
  \) \
  -delete

echo "Repository cleanup complete."
