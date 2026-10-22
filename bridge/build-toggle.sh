#!/bin/bash
# Rebuild the **Automatic Drive Sync** app in `Apps/` from its source.
#
# The app is an AppleScript applet. Its script used to exist *only* as the
# compiled copy inside the bundle, with no source anywhere — which is why the
# dialogs went on telling him the sync ran "every five minutes" for two days
# after that number had been corrected in every note and README. Nobody could
# see the one text he actually reads. Ref 193.
#
# The icon, the Info.plist and the applet binary are left exactly as they are;
# only the script is replaced, and the ad-hoc signature is renewed after — a
# bundle whose contents no longer match its signature will not launch.

set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="bridge/Automatic Drive Sync.applescript"
APP="Apps/Automatic Drive Sync.app"

[ -f "$SOURCE" ] || { echo "no source at $SOURCE"; exit 1; }
[ -d "$APP" ] || { echo "no app at $APP"; exit 1; }

TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

osacompile -o "$TEMP/main.scpt" "$SOURCE"
cp "$TEMP/main.scpt" "$APP/Contents/Resources/Scripts/main.scpt"
codesign -f -s - "$APP" >/dev/null 2>&1
codesign -v "$APP" || { echo "the rebuilt app will not launch"; exit 1; }

echo "Automatic Drive Sync rebuilt."
