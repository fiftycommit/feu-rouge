#!/bin/bash
# Compile l'app barre de menus dans un bundle .app minimal.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/FeuRouge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/FeuRouge" src/main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FeuRouge</string>
  <key>CFBundleDisplayName</key><string>Feu Rouge Codex</string>
  <key>CFBundleIdentifier</key><string>fr.max.feurouge</string>
  <key>CFBundleExecutable</key><string>FeuRouge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true
echo "OK -> $APP"
