#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

required_files=(
  Package.swift
  Info.plist
  build.sh
  make-dmg.sh
  README.md
  LICENSE
  SECURITY.md
  .gitignore
  Resources/PrivacyInfo.xcprivacy
  Sources/AirControll/AirControllApp.swift
  Sources/AirControll/AppDelegate.swift
  Sources/AirControll/AppModel.swift
  Sources/AirControll/CameraCaptureService.swift
  Sources/AirControll/FeatureExtractor.swift
  Sources/AirControll/GestureRecognizer.swift
  Sources/AirControll/ActionExecutor.swift
  Sources/AirControll/StateStore.swift
)

for path in "${required_files[@]}"; do
  [[ -f "$path" ]] || {
    echo "Missing required file: $path" >&2
    exit 1
  }
done

icon_found=false
for path in \
  icon.png icon.icns icon.icon \
  Assets/icon.png Assets/icon.icns Assets/icon.icon \
  Assets/AirControllIcon.png Assets/AirControllIcon.icns
do
  if [[ -f "$path" ]]; then
    icon_found=true
    break
  fi
done
[[ "$icon_found" == true ]] || {
  echo "Missing application icon. Add icon.png or icon.icns beside build.sh." >&2
  exit 1
}

swift package dump-package >/dev/null
plutil -lint Info.plist >/dev/null
plutil -lint Resources/PrivacyInfo.xcprivacy >/dev/null

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)" == "0.1.5" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)" == "13.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' Info.plist)" == "false" ]]

status_item_count="$(grep -R --include='*.swift' -F 'NSStatusBar.system.statusItem' Sources | wc -l | tr -d ' ')"
[[ "$status_item_count" == "1" ]] || {
  echo "Expected exactly one NSStatusItem creation; found $status_item_count." >&2
  exit 1
}

if grep -R --include='*.swift' -q 'MenuBarExtra' Sources; then
  echo "MenuBarExtra is not permitted." >&2
  exit 1
fi

for gesture in \
  'case closedFist = "Closed Fist"' \
  'case prayingHands = "Praying Hands"' \
  'case thumbsUp = "Thumbs Up"' \
  'case thumbsDown = "Thumbs Down"'
do
  grep -Fq "$gesture" Sources/AirControll/Models.swift || {
    echo "Missing built-in gesture declaration: $gesture" >&2
    exit 1
  }
done

for action in \
  'Play/Pause' 'Next Track' 'Previous Track' 'Volume Up' 'Volume Down' 'Mute' \
  'Brightness Up' 'Brightness Down' 'Mission Control' 'Show Desktop' 'Lock Screen' \
  'Screenshot' 'Open Application' 'Keyboard Shortcut' 'Do Nothing'
do
  grep -Fq "$action" Sources/AirControll/Models.swift || {
    echo "Missing supported action: $action" >&2
    exit 1
  }
done

grep -Fq 'output.alwaysDiscardsLateVideoFrames = true' Sources/AirControll/CameraCaptureService.swift
grep -Fq 'VNDetectHumanHandPoseRequest()' Sources/AirControll/CameraCaptureService.swift
grep -Fq 'guard acceptingFrames, !processingFrame' Sources/AirControll/CameraCaptureService.swift
grep -Fq 'min(15, max(10, framesPerSecond))' Sources/AirControll/CameraCaptureService.swift
grep -Fq 'Camera frames are processed locally in memory and are not saved.' \
  Sources/AirControll/Views/PrivacySettingsView.swift
grep -Fq 'case both' Sources/AirControll/Models.swift
grep -Fq 'mirroredOneHandValues' Sources/AirControll/GestureRecognizer.swift
grep -Fq 'isModifierOnly' Sources/AirControll/Models.swift

if grep -R --include='*.swift' -Eqi \
  'URLSession|Network\.framework|import Network|NWConnection|WebSocket' Sources
then
  echo "Unexpected networking API reference found." >&2
  exit 1
fi


if grep -R --include='*.swift' -Eqi   'gesture-state\.backup|quarantineCorruptFile|recoveredFromBackup|recoveryMessage'   Sources
then
  echo "Legacy backup or corruption-recovery code found." >&2
  exit 1
fi

grep -Fq 'Copyright © 2026 Argyrios.' Info.plist
grep -Fq 'Mozilla Public License Version 2.0' LICENSE

if grep -R -Eqi 'TODO|FIXME|PLACEHOLDER|fatalError\(' \
  --exclude-dir='.build' \
  --exclude-dir='.git' \
  --exclude-dir='AirControll.app' \
  --exclude='validate-repository.sh' \
  --exclude='*.zip' \
  .
then
  echo "Incomplete implementation marker found." >&2
  exit 1
fi

echo "Repository validation passed."
