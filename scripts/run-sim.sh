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
# By default uses Xcode’s normal DerivedData (same cache as Xcode / bare xcodebuild).
# Optional: DERIVED_DATA=/path/to/project-derived-data for an isolated build root.
# Do not set DERIVED_DATA to the parent …/Xcode/DerivedData folder — that is not
# the default layout and will not share Xcode’s Nostur-<hash> cache.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-Nostur}"
BUNDLE_ID="${BUNDLE_ID:-nostur.com.Nostur}"
DEVICE="${DEVICE:-iPhone 17 Pro}"
DO_BUILD=1
DO_LAUNCH=1

# Optional isolated DerivedData. Empty = Xcode default (…/DerivedData/Nostur-<hash>/).
DERIVED_DATA="${DERIVED_DATA:-}"
DEFAULT_DD_PARENT="${HOME}/Library/Developer/Xcode/DerivedData"

# If someone exported the parent DerivedData folder (common .zshrc mistake), ignore it
# so we actually share the default per-project cache with Xcode / CLI builds.
if [[ -n "$DERIVED_DATA" ]]; then
  resolved_dd="$(cd "$DERIVED_DATA" 2>/dev/null && pwd)" || resolved_dd=""
  resolved_parent="$(cd "$DEFAULT_DD_PARENT" 2>/dev/null && pwd)" || resolved_parent=""
  if [[ -n "$resolved_dd" && -n "$resolved_parent" && "$resolved_dd" == "$resolved_parent" ]]; then
    echo "==> Note: DERIVED_DATA points at the Xcode parent folder; using default per-project DerivedData instead"
    DERIVED_DATA=""
  fi
fi

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
  DERIVED_DATA  Optional isolated build root. Leave unset to use Xcode’s default
                DerivedData (shared with Xcode / bare xcodebuild). Do not set this
                to the parent …/Xcode/DerivedData folder.
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
if [[ -n "$DERIVED_DATA" ]]; then
  echo "==> DerivedData: ${DERIVED_DATA} (custom)"
else
  echo "==> DerivedData: default (Xcode …/DerivedData/Nostur-*/)"
fi
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

XCODEBUILD_ARGS=(
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -quiet
)
if [[ -n "$DERIVED_DATA" ]]; then
  XCODEBUILD_ARGS+=(-derivedDataPath "$DERIVED_DATA")
fi

if [[ "$DO_BUILD" -eq 1 ]]; then
  echo "==> Building..."
  xcodebuild "${XCODEBUILD_ARGS[@]}" build
  echo "==> Build succeeded"
fi

# Resolve Nostur.app from build settings (respects default or custom DerivedData).
resolve_app_path() {
  local settings products_dir
  local sb_args=(-scheme "$SCHEME" -destination "$DESTINATION")
  if [[ -n "$DERIVED_DATA" ]]; then
    sb_args+=(-derivedDataPath "$DERIVED_DATA")
  fi
  settings="$(xcodebuild "${sb_args[@]}" -showBuildSettings 2>/dev/null)" || true
  products_dir="$(printf '%s\n' "$settings" | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)"
  if [[ -n "$products_dir" && -d "${products_dir}/Nostur.app" ]]; then
    printf '%s\n' "${products_dir}/Nostur.app"
    return 0
  fi

  # Fallback: newest Debug-iphonesimulator product under the relevant root
  local search_root="${DERIVED_DATA:-$DEFAULT_DD_PARENT}"
  find "$search_root" -name 'Nostur.app' -path '*/Debug-iphonesimulator/*' 2>/dev/null \
    | while IFS= read -r p; do
        [[ -d "$p" ]] || continue
        # mtime (epoch) then path — newest first
        stat -f '%m %N' "$p" 2>/dev/null || true
      done \
    | sort -rn \
    | head -1 \
    | cut -d' ' -f2-
}

APP_PATH="$(resolve_app_path)"
if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "error: could not find Nostur.app"
  echo "Run without --no-build first (or check DERIVED_DATA)."
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
