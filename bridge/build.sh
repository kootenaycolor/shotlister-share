#!/bin/bash
# Builds the syncer into an app bundle of its own.
#
# A bundle rather than a loose binary because Full Disk Access is granted to a
# thing you can point at in System Settings, and this is that thing. It has no
# window and never appears in the Dock — it is a worker, not an app he opens.

set -euo pipefail
cd "$(dirname "$0")"

APP="Shotlister Drive Sync.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Shotlister Drive Sync</string>
  <key>CFBundleDisplayName</key><string>Shotlister Drive Sync</string>
  <key>CFBundleIdentifier</key><string>com.example.shotlister.drivesync</string>
  <key>CFBundleExecutable</key><string>drivesync</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- No Dock icon, no menu bar. It does a job and exits. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# The same engine both apps use. The bridge asks it what a location is called
# and which photographs belong to it, rather than guessing from folder names —
# guessing is what made a deleted photograph indistinguishable from a new one.
ROOT="$(cd .. && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
( cd "$ROOT/ffi" && cargo build --release --offline --quiet )
LIB="$ROOT/ffi/target/release/libshotlister_ffi.a"
[ -f "$LIB" ] || { echo "the engine did not build"; exit 1; }

swiftc -O -target arm64-apple-macos14.0 \
  -import-objc-header "$ROOT/ffi/include/shotlister.h" \
  Sources/main.swift "$ROOT/shared/FileNames.swift" "$ROOT/shared/DeviceIdentity.swift" "$LIB" \
  -o "$APP/Contents/MacOS/drivesync"

cp projects.txt "$APP/Contents/Resources/projects.txt"

# Ad-hoc, but a stable identifier — which is what Full Disk Access remembers.
codesign --force --sign - --identifier com.example.shotlister.drivesync "$APP"

echo "✓ $(pwd)/$APP"
