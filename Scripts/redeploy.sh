#!/bin/zsh
# Rebuilds RepLog (refreshing the free-account 7-day provisioning profile)
# and installs it to your iPhone over Wi-Fi. Run by launchd twice a week.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PROJ="/Users/YOUR_USERNAME/Downloads/Projects/RepLog"
DEVICE="00000000-0000-0000-0000-000000000000"
LOG="$HOME/Library/Logs/replog-redeploy.log"

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"RepLog redeploy\"" || true
}

run() {
  echo "=== $(date) redeploy start"
  cd "$PROJ"
  /opt/homebrew/bin/xcodegen generate
  xcodebuild -scheme RepLog -destination 'generic/platform=iOS' -allowProvisioningUpdates build
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*Debug-iphoneos/RepLog.app" -not -path "*Index.noindex*" | head -1)
  [ -n "$APP" ] || { echo "no built app found"; return 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  echo "=== $(date) redeploy success"
}

if run >> "$LOG" 2>&1; then
  notify "iPhone app refreshed ✓ (next expiry reset)"
else
  notify "FAILED — phone on Wi-Fi? See ~/Library/Logs/replog-redeploy.log"
  exit 1
fi
