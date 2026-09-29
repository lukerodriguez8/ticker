#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Ticker.app"
SOURCES=(main.swift Content.swift Marquee.swift Wikiquote.swift Ratings.swift Feeds.swift)
FLAGS=()

# some Command Line Tools installs ship a duplicate SwiftBridging modulemap that breaks builds
CLT_SWIFT=/Library/Developer/CommandLineTools/usr/include/swift
if [[ -f $CLT_SWIFT/module.modulemap && -f $CLT_SWIFT/bridging.modulemap ]]; then
  WORK=$(mktemp -d)
  : > "$WORK/empty.modulemap"
  cat > "$WORK/overlay.yaml" <<OVERLAY
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "file", "name": "$CLT_SWIFT/module.modulemap", "external-contents": "$WORK/empty.modulemap" } ] }
OVERLAY
  FLAGS=(-vfsoverlay "$WORK/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$WORK/overlay.yaml")
fi

pkill -x Ticker 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O "${SOURCES[@]}" "${FLAGS[@]}" -o "$APP/Contents/MacOS/Ticker" -framework AppKit

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ticker</string>
  <key>CFBundleIdentifier</key><string>local.ticker</string>
  <key>CFBundleExecutable</key><string>Ticker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
open "$APP"
echo "Ticker is running from $APP"
