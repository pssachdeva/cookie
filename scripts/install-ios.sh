#!/bin/zsh
# Builds the iPhone app and installs it on the connected iPhone (cable or
# Wi-Fi, once "Connect via network" is enabled in Xcode's Devices window).
#
# Usage: scripts/install-ios.sh [--release]
# The phone must be unlocked. DEVICE=<name or UDID> picks a device when more
# than one is connected.
set -euo pipefail

cd "$(dirname "$0")/.."
config=Debug
for arg in "$@"; do
  case "$arg" in
    --release) config=Release ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Pick the physical iPhone (its UDID works for both xcodebuild and devicectl).
udid="$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, os, sys
want = os.environ.get("DEVICE", "")
phones = [d for d in json.load(sys.stdin)["result"]["devices"]
          if d["hardwareProperties"].get("reality") == "physical"]
if want:
    phones = [d for d in phones if want in (d["deviceProperties"].get("name", ""), d["hardwareProperties"].get("udid", ""), d["identifier"])]
# Prefer a phone that is reachable right now.
phones.sort(key=lambda d: d["connectionProperties"].get("tunnelState") != "connected")
print(phones[0]["hardwareProperties"]["udid"] if phones else "")
')"
if [[ -z "$udid" ]]; then
  echo "no iPhone is paired with this Mac; connect it with a cable once and trust the computer" >&2
  exit 1
fi

derived=.build/xcode-ios
log="$derived/build.log"
mkdir -p "$derived"
if ! xcodebuild \
  -project Cookie.xcodeproj \
  -scheme "Cookie iOS" \
  -configuration "$config" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$derived" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build >"$log" 2>&1
then
  grep -E "error:" "$log" | sort -u >&2
  echo "build failed; full log: $log" >&2
  exit 1
fi

app="$derived/Build/Products/$config-iphoneos/Cookie.app"
if ! xcrun devicectl device install app --device "$udid" "$app" >/dev/null 2>"$derived/install.err"; then
  echo "built, but could not reach the iPhone to install: unlock it and check the cable or Wi-Fi connection" >&2
  tail -3 "$derived/install.err" >&2
  exit 1
fi
xcrun devicectl device process launch --device "$udid" --terminate-existing com.psachdeva.cookie >/dev/null
echo "installed and launched Cookie ($config) on iPhone $udid"
