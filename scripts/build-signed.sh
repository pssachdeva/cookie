#!/bin/zsh
# Builds the signed, iCloud-enabled app from Cookie.xcodeproj.
#
# Usage: scripts/build-signed.sh [--debug] [--install]
#   --debug    Debug configuration instead of Release.
#   --install  Quit Cookie if it's running, replace /Applications/Cookie.app
#              with the new build, and open it.
#
# Signing is automatic: Xcode must be signed in to the developer account
# (Xcode > Settings > Accounts) and the team chosen once under the Cookie
# target's Signing & Capabilities. DEVELOPMENT_TEAM=<team ID> overrides it.
set -euo pipefail

cd "$(dirname "$0")/.."
config=Release
install=0
for arg in "$@"; do
  case "$arg" in
    --debug) config=Debug ;;
    --install) install=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
team_setting=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  team_setting=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

derived=.build/xcode
log="$derived/build.log"
mkdir -p "$derived"
if ! xcodebuild \
  -project Cookie.xcodeproj \
  -scheme Cookie \
  -configuration "$config" \
  -derivedDataPath "$derived" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${team_setting[@]}" \
  build >"$log" 2>&1
then
  grep -E "error:" "$log" | sort -u >&2
  echo "build failed; full log: $log" >&2
  exit 1
fi
grep -E "warning: " "$log" | grep -v "appintentsmetadataprocessor" | sort -u || true

app="$derived/Build/Products/$config/Cookie.app"
codesign --verify --strict "$app"
echo "built $app ($config)"

if (( install )); then
  osascript -e 'tell application id "com.psachdeva.cookie" to quit' 2>/dev/null || true
  # Wait on the Mac app by bundle ID: the iPhone app running in the
  # Simulator is also a process named Cookie.
  while [[ "$(osascript -e 'application id "com.psachdeva.cookie" is running' 2>/dev/null)" == "true" ]]; do sleep 0.2; done
  rm -rf /Applications/Cookie.app
  ditto "$app" /Applications/Cookie.app
  # Launch Services can refuse (-600) for a moment after the old copy
  # quits; retry briefly.
  for _ in 1 2 3 4 5; do
    open /Applications/Cookie.app 2>/dev/null && break
    sleep 1
  done
  echo "installed /Applications/Cookie.app"
fi
