#!/bin/zsh
# Rebuilds RepLog (refreshing the free-account 7-day provisioning profile)
# and installs it to your iPhone over Wi-Fi. Run by launchd twice a week.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Must live outside ~/Downloads: macOS privacy protection blocks launchd
# jobs from reading it (zsh exits 127 before this script even starts).
PROJ="${0:A:h:h}"
# Per-machine value from the gitignored Local.xcconfig (see README).
DEVICE=$(sed -n 's/^REPLOG_DEVICE_ID *= *//p' "$PROJ/Local.xcconfig" 2>/dev/null || true)
[ -n "$DEVICE" ] || { echo "REPLOG_DEVICE_ID not set in $PROJ/Local.xcconfig" >&2; exit 1; }
LOG="$HOME/Library/Logs/replog-redeploy.log"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/RepLog-redeploy"

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"RepLog redeploy\"" || true
}

run() {
  echo "=== $(date) redeploy start"
  cd "$PROJ"
  /opt/homebrew/bin/xcodegen generate
  # Fixed derived-data path so we always install the app this run just built,
  # never a stale one left in another DerivedData folder.
  xcodebuild -scheme RepLog -destination 'generic/platform=iOS' -allowProvisioningUpdates \
    -derivedDataPath "$DERIVED" build
  APP="$DERIVED/Build/Products/Debug-iphoneos/RepLog.app"
  [ -d "$APP" ] || { echo "no built app found"; return 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  echo "=== $(date) redeploy success"
}

if run >> "$LOG" 2>&1; then
  notify "iPhone app refreshed ✓ (next expiry reset)"
else
  notify "FAILED — phone on Wi-Fi? See ~/Library/Logs/replog-redeploy.log"
  exit 1
fi
