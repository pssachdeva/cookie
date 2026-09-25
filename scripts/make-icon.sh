#!/bin/zsh
# Regenerates Assets/AppIcon.icns from Assets/AppIcon.svg.
# build-app.sh runs this automatically when the .icns is missing or older than the SVG.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
iconset="$(mktemp -d)/AppIcon.iconset"
swift scripts/render-icon.swift Assets/AppIcon.svg "$iconset"
iconutil -c icns "$iconset" -o Assets/AppIcon.icns
rm -rf "$(dirname "$iconset")"
echo "wrote Assets/AppIcon.icns"
