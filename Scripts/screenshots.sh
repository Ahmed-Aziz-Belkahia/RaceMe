#!/usr/bin/env bash
#
# Boots a simulator, installs RaceMe, and walks it through every screen taking
# a PNG of each. No UI test target involved — the app routes itself from the
# -demoScreen launch argument.
#
#   ./Scripts/screenshots.sh                       # iPhone 17 Pro, default
#   ./Scripts/screenshots.sh "iPhone 17 Pro Max"   # pick a device
#
# Output lands in ./screenshots/.
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro}"
SCHEME="RaceMe"
BUNDLE_ID="com.raceme.RaceMe"
OUT="screenshots"
DERIVED="$(mktemp -d)"

SCREENS=(
  coldOpen hook pace compute card paywall
  home race postRace board profile spectate
)

echo "==> Building $SCHEME for the simulator"
xcodebuild \
  -project RaceMe.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
[ -d "$APP" ] || { echo "No app at $APP"; exit 1; }

echo "==> Booting $DEVICE"
UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | grep -oE '[0-9A-F-]{36}')
[ -n "$UDID" ] || { echo "No available simulator called '$DEVICE'"; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
# Dark only — the app forces it anyway, but this keeps the status bar honest.
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "5:31" --batteryState charged --batteryLevel 100 --cellularBars 4

mkdir -p "$OUT"

for SCREEN in "${SCREENS[@]}"; do
  echo "==> $SCREEN"
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -demoScreen "$SCREEN" -demoFreeze YES >/dev/null

  # Let the screen settle. The race and compute screens are timed sequences, so
  # they get long enough to reach the part worth looking at.
  case "$SCREEN" in
    race)      sleep 14 ;;   # past the countdown, into the running lane
    compute)   sleep 3  ;;   # mid-way through the narrated steps
    coldOpen)  sleep 4  ;;   # after the photo finish resolves into the wordmark
    postRace)  sleep 3  ;;   # after the print has developed
    *)         sleep 2  ;;
  esac

  xcrun simctl io "$UDID" screenshot --type png "$OUT/$SCREEN.png"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
done

rm -rf "$DERIVED"
echo "==> Done. $(ls -1 "$OUT" | wc -l | tr -d ' ') screenshots in $OUT/"
