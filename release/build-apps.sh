#!/bin/bash
# Rebuilds the two double-click apps in `Apps/` from the AppleScript
# beside this file.
#
# Same lesson as bridge/build-toggle.sh: the compiled script inside an applet is
# not readable, so a bundle with no source is a text nobody can correct. The
# source lives here; the applet is generated.
#
# **The icon is carried over, not regenerated.** Every double-click app at the
# root wears the same icon, and nothing in the repo builds it -- it was put on
# by hand once. `osacompile` writes a fresh bundle with Apple's generic applet
# icon, so without the copying below, rebuilding either app silently swaps its
# icon on his desktop for a white page with a pencil. He finds these by their
# icon. Taken from the app being rebuilt, or from any sibling that still has
# one, so a fresh checkout still comes out right.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

icon_source() {
  local want="$1"
  [ -f "$want/Contents/Resources/Assets.car" ] && { echo "$want"; return; }
  local other
  for other in "$ROOT"/Apps/*.app; do
    [ -f "$other/Contents/Resources/Assets.car" ] && { echo "$other"; return; }
  done
}

for name in "Release Shotlister" "Set Up Releasing"; do
  APP="$ROOT/Apps/$name.app"
  FROM="$(icon_source "$APP")"
  KEEP=""
  if [ -n "$FROM" ]; then
    KEEP="$(mktemp -d)"
    cp "$FROM/Contents/Resources/Assets.car" "$KEEP/"
    cp "$FROM/Contents/Resources/applet.icns" "$KEEP/" 2>/dev/null || true
  else
    echo "  no icon to carry over — $name.app will wear the generic applet icon"
  fi

  rm -rf "$APP"
  osacompile -o "$APP" "$name.applescript"

  # Before signing: changing a resource after the signature invalidates it, and
  # macOS refuses to launch an applet whose signature does not match.
  if [ -n "$KEEP" ]; then
    cp "$KEEP/Assets.car" "$APP/Contents/Resources/"
    [ -f "$KEEP/applet.icns" ] && cp "$KEEP/applet.icns" "$APP/Contents/Resources/"
    rm -rf "$KEEP"
  fi

  codesign -f -s - "$APP" >/dev/null 2>&1
  codesign -v "$APP" || { echo "$name will not launch"; exit 1; }
  echo "✓ $name.app"
done
