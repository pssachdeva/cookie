#!/bin/zsh
# Builds the CookieApp executable with SwiftPM and assembles build/Cookie.app.
# An .app bundle is needed for a Dock icon and menu-bar item; a bare binary
# runs as a faceless process.
#
# Usage: scripts/build-app.sh [--release] [--run]
set -euo pipefail

cd "$(dirname "$0")/.."
config=debug
run=0
for arg in "$@"; do
  case "$arg" in
    --release) config=release ;;
    --run) run=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c "$config" --product CookieApp

# Regenerate the Dock icon when the SVG is newer than the .icns (or the .icns is missing).
icns=Assets/AppIcon.icns
if [[ ! -f "$icns" || Assets/AppIcon.svg -nt "$icns" ]]; then
  scripts/make-icon.sh
fi

bin_dir="$(swift build -c "$config" --show-bin-path)"
app=build/Cookie.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/CookieApp" "$app/Contents/MacOS/Cookie"
cp "$icns" "$app/Contents/Resources/AppIcon.icns"
# The in-app cookie glyph (checkbox animation) renders this SVG at runtime.
cp Assets/AppIcon.svg "$app/Contents/Resources/AppIcon.svg"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Cookie</string>
  <key>CFBundleDisplayName</key><string>Cookie</string>
  <key>CFBundleIdentifier</key><string>com.psachdeva.cookie</string>
  <key>CFBundleExecutable</key><string>Cookie</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string></string>
</dict>
</plist>
EOF

# Ad-hoc signature so macOS treats the bundle as a stable identity.
codesign --force --sign - "$app" >/dev/null

echo "built $app ($config)"
if (( run )); then
  open "$app"
fi
