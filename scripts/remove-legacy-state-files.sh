#!/bin/bash
set -euo pipefail

STATE_DIR="$HOME/Library/Application Support/AirControll"

if [[ ! -d "$STATE_DIR" ]]; then
  echo "No AirControll Application Support folder exists."
  exit 0
fi

rm -f "$STATE_DIR/gesture-state.backup.json"

find "$STATE_DIR" -maxdepth 1 -type f \
  \( \
    -name 'gesture-state.corrupt-*.json' -o \
    -name 'gesture-state.backup.corrupt-*.json' -o \
    -name 'gesture-state.recovery-*.tmp' -o \
    -name 'gesture-state.tmp-*' \
  \) \
  -delete

printf 'Legacy backup and recovery files removed from:\n%s\n' "$STATE_DIR"
