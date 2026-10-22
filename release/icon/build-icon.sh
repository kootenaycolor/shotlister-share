#!/bin/bash
# Compiles release/icon/Shotlister.icon into the two files the app bundle wants.
#
# **The icon is an Icon Composer document, not a picture.** `Shotlister.icon` is
# a folder holding one SVG and a description of how macOS should light it;
# `actool` — Apple's own asset compiler, the same one Xcode calls — turns that
# into the Liquid Glass icon. That is what gives it the depth and the moving
# highlight rather than us drawing a fake one, and it is why the source here is
# flat artwork with no shadow or shine painted into it.
#
# Two files come out, and the bundle needs both:
#
#   Assets.car        the glass icon, used by macOS 26 and later
#   Shotlister.icns   a flat rendering, used by macOS 14 and 15
#
# Open the .icon in Icon Composer (inside Xcode) to change it by hand:
#   open -a "/Applications/Xcode.app/Contents/Applications/Icon Composer.app" \
#        release/icon/Shotlister.icon

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# The deployment target matches the app's LSMinimumSystemVersion, so actool
# emits the fallback for the older systems the app still claims to run on.
xcrun actool Shotlister.icon \
  --compile "$OUT" \
  --app-icon Shotlister \
  --output-partial-info-plist "$OUT/partial.plist" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --errors --warnings >/dev/null

[ -f "$OUT/Assets.car" ] || { echo "actool produced no Assets.car"; exit 1; }
[ -f "$OUT/Shotlister.icns" ] || { echo "actool produced no fallback icns"; exit 1; }

cp "$OUT/Assets.car" "$ROOT/release/Assets.car"
cp "$OUT/Shotlister.icns" "$ROOT/release/Shotlister.icns"
echo "✓ release/Assets.car and release/Shotlister.icns"
