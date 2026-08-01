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

mkdir -p "$OUT/logs"

for SCREEN in "${SCREENS[@]}"; do
  echo "==> $SCREEN"
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"

  # --console-pty streams the app's stdout/stderr, which is the only window into
  # a headless run: DemoMode.log lines, SwiftUI runtime complaints, and the
  # message from any fatalError all come out here. It blocks for the life of the
  # process, so it runs in the background and gets killed after the capture.
  xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" \
    -demoScreen "$SCREEN" -demoFreeze YES > "$OUT/logs/$SCREEN.log" 2>&1 &
  CONSOLE_PID=$!

  # Let the screen settle.
  #
  # These are generous on purpose. The app is reinstalled before each capture so
  # every launch is cold, and a cold SwiftUI start on a CI simulator can take
  # several seconds before the first frame of real content. Screenshotting too
  # early catches entrance animations at opacity zero and produces a series of
  # beautifully composed empty screens — which is exactly what the first run of
  # this script did.
  #
  # -demoFreeze also collapses entrance animations to their end state, so this
  # only has to outlast the launch, not the choreography.
  case "$SCREEN" in
    race)      sleep 22 ;;   # cold start + 3-2-1 countdown + enough race to leave trails
    compute)   sleep 12 ;;   # the narrated steps run 4-6s of real work
    coldOpen)  sleep 10 ;;   # the 3s film has to resolve into the wordmark first
    postRace)  sleep 10 ;;   # after the print has developed
    hook)      sleep 10 ;;
    *)         sleep 9  ;;
  esac

  xcrun simctl io "$UDID" screenshot --type png "$OUT/$SCREEN.png"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  kill "$CONSOLE_PID" 2>/dev/null || true
  wait "$CONSOLE_PID" 2>/dev/null || true

  echo "    $(grep -c 'RACEME-DEMO' "$OUT/logs/$SCREEN.log" 2>/dev/null || echo 0) demo log lines"
done

# Anything that crashed lands here. Empty is the good outcome.
mkdir -p "$OUT/crashes"
find ~/Library/Logs/DiagnosticReports -name '*RaceMe*' -mmin -60 \
  -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true

rm -rf "$DERIVED"
echo "==> Done. $(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') screenshots, $(ls -1 "$OUT"/crashes 2>/dev/null | wc -l | tr -d ' ') crash reports."
