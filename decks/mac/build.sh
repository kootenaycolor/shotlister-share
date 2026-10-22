#!/bin/bash
# Build Deck Editor.app.
#
# macOS ties permissions to an app's exact signature, so every rebuild is a new
# app as far as the system is concerned. This one deliberately needs no
# permission at all — since 2026-09-05 it reads no folder, starts no process and
# opens no Terminal; it is a window on the portal, where the editor now lives.
# That is what keeps a rebuild cheap. Keep it that way.
set -e
cd "$(dirname "$0")"
# **The repo root, beside Rebuild Shotlister.app** — one known place for the
# things he double-clicks. Since the fold this file sits two levels down.
ROOT="$(cd ../.. && pwd)"
APP="$ROOT/Deck Editor.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc \
  -O -swift-version 5 -parse-as-library \
  -sdk "$SDK" -target arm64-apple-macos26.0 \
  -framework SwiftUI -framework AppKit -framework WebKit \
  -o "$APP/Contents/MacOS/DeckEditor" \
  Sources/*.swift

codesign --force --sign - "$APP"
touch "$APP"
echo "built $APP"
