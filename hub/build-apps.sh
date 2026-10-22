#!/bin/bash
# Rebuild the hub's double-click apps in `Apps/` from the AppleScript beside
# this file. Same shape as `release/build-apps.sh`, for the same reason: the
# compiled script inside an applet is not readable, so the source lives here
# and the bundle is generated.
#
#   hub/build-apps.sh                 every app listed below
#   hub/build-apps.sh "Deploy Shotlister"   one of them
#
# **The icon is carried over.** `osacompile` writes a bundle wearing Apple's
# generic applet icon; every app in `Apps/` wears the same Shotlister icon,
# put on by hand once and nowhere in the repo. It is taken from the app being
# rebuilt, or from any sibling that still has one.
#
# **A helper rides inside some of them.** The two spec sheet apps carry
# `hub/spec-sheets.py` in their Resources, so the app works from wherever it
# sits and does not depend on which checkout is on disk.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

APPS=("Deploy Shotlister" "Update the Portal" "Move Spec Sheets" "Spec Sheet Switch")
[ $# -gt 0 ] && APPS=("$@")

icon_source() {
  local want="$1"
  [ -f "$want/Contents/Resources/Assets.car" ] && { echo "$want"; return; }
  local other
  for other in "$ROOT"/Apps/*.app; do
    [ -f "$other/Contents/Resources/Assets.car" ] && { echo "$other"; return; }
  done
}

for name in "${APPS[@]}"; do
  [ -f "$name.applescript" ] || { echo "no source at hub/$name.applescript"; exit 1; }
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

  # Before signing: a resource changed after the signature will not launch.
  if [ -n "$KEEP" ]; then
    cp "$KEEP/Assets.car" "$APP/Contents/Resources/"
    [ -f "$KEEP/applet.icns" ] && cp "$KEEP/applet.icns" "$APP/Contents/Resources/"
    rm -rf "$KEEP"
  fi
  case "$name" in
    "Move Spec Sheets"|"Spec Sheet Switch")
      cp spec-sheets.py "$APP/Contents/Resources/spec-sheets.py"
      chmod 755 "$APP/Contents/Resources/spec-sheets.py" ;;
  esac

  codesign -f -s - "$APP" >/dev/null 2>&1
  codesign -v "$APP" || { echo "$name will not launch"; exit 1; }
  echo "✓ Apps/$name.app"
done
