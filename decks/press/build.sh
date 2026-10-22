#!/bin/bash
# Builds the press into an app bundle of its own — see Sources/main.swift for
# why. No window, never in the Dock; it runs the printer once and exits.
set -euo pipefail
cd "$(dirname "$0")"
APP="../Shotlister Deck Press.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Shotlister Deck Press</string>
  <key>CFBundleDisplayName</key><string>Shotlister Deck Press</string>
  <key>CFBundleIdentifier</key><string>com.example.shotlister.deckpress</string>
  <key>CFBundleExecutable</key><string>deckpress</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
swiftc -O -target arm64-apple-macos14.0 Sources/main.swift -o "$APP/Contents/MacOS/deckpress"
# Ad-hoc, but a stable identifier — which is what Full Disk Access remembers.
codesign --force --sign - --identifier com.example.shotlister.deckpress "$APP"
echo "✓ $(cd .. && pwd)/Shotlister Deck Press.app"
