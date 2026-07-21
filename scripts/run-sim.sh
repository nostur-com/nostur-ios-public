#!/usr/bin/env bash
# Build, install, and launch Nostur on the iOS Simulator (Xcode Play equivalent).
#
# Usage:
#   ./scripts/run-sim.sh
#   ./scripts/run-sim.sh "iPhone 17 Pro"
#   DEVICE="iPhone Air" ./scripts/run-sim.sh
#   ./scripts/run-sim.sh --build-only
#   ./scripts/run-sim.sh --no-build   # reinstall/launch last build only
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-Nostur}"
BUNDLE_ID="${BUNDLE_ID:-nostur.com.Nostur}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/NosturDerived}"
DEVICE="${DEVICE:-iPhone 17 Pro}"
DO_BUILD=1
DO_LAUNCH=1

for arg in "$@"; do
  case "$arg" in
    --build-only)
      DO_LAUNCH=0
      ;;
    --no-build)
      DO_BUILD=0
      ;;
    --help|-h)
      cat <<'HELP'
Build, install, and launch Nostur on the iOS Simulator (Xcode Play equivalent).

Usage:
  ./scripts/run-sim.sh
  ./scripts/run-sim.sh "iPhone 17 Pro"
  DEVICE="iPhone Air" ./scripts/run-sim.sh
  ./scripts/run-sim.sh --build-only
  ./scripts/run-sim.sh --no-build   # reinstall/launch last build only

Env:
  DEVICE        Simulator name (default: iPhone 17 Pro)
  SCHEME        Xcode scheme (default: Nostur)
  BUNDLE_ID     App id (default: nostur.com.Nostur)
  DERIVED_DATA  Build products path (default: /tmp/NosturDerived)
HELP
      exit 0
      ;;
    *)
      DEVICE="$arg"
      ;;
  esac
done

echo "==> Device:      ${DEVICE}"
echo "==> Scheme:      ${SCHEME}"
echo "==> DerivedData: ${DERIVED_DATA}"
echo "==> Bundle ID:   ${BUNDLE_ID}"

# Resolve device name -> UDID (first available match)
UDID="$(xcrun simctl list devices available | awk -v name="$DEVICE" '
  index($0, name) && $0 ~ /\([A-F0-9-]{36}\)/ {
    if (match($0, /\([A-F0-9-]{36}\)/)) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  }
')"

if [[ -z "${UDID:-}" ]]; then
  echo "error: no available simulator named \"$DEVICE\""
  echo "Available devices:"
  xcrun simctl list devices available | grep -E "iPhone|iPad" || true
  exit 1
fi

echo "==> UDID:        ${UDID}"

# Boot only our target first (before opening Simulator.app).
STATE="$(xcrun simctl list devices | grep "$UDID" | grep -oE '\((Shutdown|Booted|Booting)\)' | head -1 || true)"
if [[ "$STATE" != "(Booted)" ]]; then
  echo "==> Booting simulator..."
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b
fi

# Shut down any other booted simulators so Simulator.app doesn't open extra windows.
# (open -a Simulator restores last-used devices; CurrentDeviceUDID may differ from our target.)
while read -r other_udid; do
  [[ -z "$other_udid" || "$other_udid" == "$UDID" ]] && continue
  echo "==> Shutting down other simulator: $other_udid"
  xcrun simctl shutdown "$other_udid" 2>/dev/null || true
done < <(xcrun simctl list devices | awk -F '[()]' '/\(Booted\)/ { print $2 }')

# Point Simulator.app at our device so it doesn't reopen a different last-used one.
defaults write com.apple.iphonesimulator CurrentDeviceUDID "$UDID"

open -a Simulator

DESTINATION="platform=iOS Simulator,id=${UDID}"

if [[ "$DO_BUILD" -eq 1 ]]; then
  echo "==> Building..."
  xcodebuild \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    build
  echo "==> Build succeeded"
fi

APP_PATH="$(find "$DERIVED_DATA" -name 'Nostur.app' -path '*/Debug-iphonesimulator/*' 2>/dev/null | head -1)"
if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "error: could not find Nostur.app under $DERIVED_DATA"
  echo "Run without --no-build first."
  exit 1
fi

echo "==> Installing: $APP_PATH"
xcrun simctl install "$UDID" "$APP_PATH"

if [[ "$DO_LAUNCH" -eq 1 ]]; then
  echo "==> Launching $BUNDLE_ID"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
  echo "==> Done"
else
  echo "==> Build-only complete (not launching)"
fi
