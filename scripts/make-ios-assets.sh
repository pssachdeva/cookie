#!/bin/zsh
# Regenerates the iPhone app's images in App/iOS/Assets.xcassets from
# Assets/AppIcon.svg: the app icon, on an opaque cream square as iOS requires,
# and the cookie drawn in checked task rows, at 1x, 2x, and 3x.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
svg=Assets/AppIcon.svg
catalog=App/iOS/Assets.xcassets

swift scripts/render-png.swift "$svg" "$catalog/AppIcon.appiconset/AppIcon.png" 1024 F6E9D3
for scale in 1 2 3; do
  swift scripts/render-png.swift "$svg" "$catalog/Cookie.imageset/Cookie@${scale}x.png" $(( 22 * scale ))
done
echo "wrote $catalog"
