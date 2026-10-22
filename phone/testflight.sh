#!/bin/bash
# Builds the iPhone app and sends it to TestFlight.
#
#   phone/testflight.sh            check, archive, export, upload
#   phone/testflight.sh --no-upload  stop after the export (a dry run)
#
# The same shape as project-console-ios/release.sh, which is the proven one:
# the App Store Connect key signs and uploads, Xcode's automatic signing makes
# whatever certificate and profile it needs, and every build takes the next
# number Apple has not seen. `Send to TestFlight.app` at the repo's top runs
# this in a Terminal window.
#
# **The app's record on App Store Connect has to exist first** — Apple's API
# cannot make one. Without it this stops before building and says so.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
# The framework Python first: it is the one with `jwt` and `certifi`, which
# the question to App Store Connect needs. Homebrew's has neither.
export PATH="/Library/Frameworks/Python.framework/Versions/Current/bin:$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

UPLOAD=yes
[ "${1:-}" = "--no-upload" ] && UPLOAD=no

KEY_ID=YOUR_KEY_ID
ISSUER=YOUR_ISSUER_ID
BUNDLE=com.example.shotlister.phone
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
VERSION="$(tr -d '[:space:]' < "$ROOT/release/VERSION")"

[ -f "$KEY_PATH" ] || { echo "No App Store Connect key at $KEY_PATH. Nothing was built."; exit 1; }

# ---- which app, and the next build number ----------------------------------
# Apple's count decides: a number it has already seen is refused, and only
# after the whole archive and upload.
ASKED="$(python3 - "$KEY_ID" "$ISSUER" "$BUNDLE" <<'EOF'
import json, os, ssl, sys, time, urllib.request
import certifi, jwt
key_id, issuer, bundle = sys.argv[1:4]
key = open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")).read()
now = int(time.time())
token = jwt.encode({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": key_id})
ctx = ssl.create_default_context(cafile=certifi.where())
def get(path):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path,
                                 headers={"Authorization": f"Bearer {token}"})
    return json.load(urllib.request.urlopen(req, context=ctx, timeout=30))["data"]
apps = get(f"/v1/apps?filter[bundleId]={bundle}&fields[apps]=bundleId")
apps = [a for a in apps if a["attributes"]["bundleId"] == bundle]
if not apps:
    print("none 0")
    sys.exit(0)
app = apps[0]["id"]
builds = get(f"/v1/builds?filter[app]={app}&fields[builds]=version&limit=200")
print(app, max([int(b["attributes"]["version"]) for b in builds if b["attributes"]["version"].isdigit()] or [0]))
EOF
)" || { echo "Could not ask App Store Connect about the app. Nothing was built."; exit 1; }
APP_ID="${ASKED% *}"
LATEST="${ASKED#* }"
if [ "$APP_ID" = "none" ] && [ "$UPLOAD" = yes ]; then
  echo "App Store Connect has no app for $BUNDLE yet."
  echo "Make it once at appstoreconnect.apple.com → Apps → + → New App, then run this again."
  echo "Nothing was built."
  exit 1
fi
NEXT=$((LATEST + 1))
echo "▸ Shotlister $VERSION, build $NEXT"

# ---- checks ------------------------------------------------------------------
echo "▸ checks"
if ./checks.sh > /tmp/shotlister-phone-checks.log 2>&1; then
  echo "   $(grep -E 'passed' /tmp/shotlister-phone-checks.log | head -1)"
else
  echo "   FAILED (see /tmp/shotlister-phone-checks.log). Nothing was uploaded."
  exit 1
fi

# ---- the engine, for the phone -----------------------------------------------
echo "▸ engine"
rustup target add aarch64-apple-ios >/dev/null 2>&1 || true
( cd "$ROOT/ffi" && cargo build --release --target aarch64-apple-ios --quiet )

# ---- the project, numbered ---------------------------------------------------
# Info.plist is written by xcodegen from project.yml, so the number goes in
# after it is generated, and the file is put back afterwards — project.yml
# keeps no build number to drift.
xcodegen generate --spec project.yml >/dev/null
cp Info.plist /tmp/shotlister-phone-Info.plist
cp Widgets/Info.plist /tmp/shotlister-phone-widgets-Info.plist
trap 'cp /tmp/shotlister-phone-Info.plist Info.plist; cp /tmp/shotlister-phone-widgets-Info.plist Widgets/Info.plist' EXIT
# The lock screen widgets carry the app's numbers; Apple refuses a widget
# whose build number differs from the app it rides in.
for PLIST in Info.plist Widgets/Info.plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
done

# ---- archive and export --------------------------------------------------------
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
OUT="$ROOT/release/out/phone"
rm -rf "$OUT"; mkdir -p "$OUT"
echo "▸ archiving"
if ! xcodebuild -project Shotlister.xcodeproj -scheme Shotlister \
     -destination 'generic/platform=iOS' -configuration Release \
     -archivePath "$OUT/Shotlister.xcarchive" "${AUTH[@]}" archive > "$OUT/archive.log" 2>&1; then
  grep -E "error:" "$OUT/archive.log" | sort -u | head -10
  echo "Archive failed (see $OUT/archive.log). Nothing was uploaded."
  exit 1
fi
echo "▸ exporting"
if ! xcodebuild -exportArchive -archivePath "$OUT/Shotlister.xcarchive" \
     -exportPath "$OUT/export" -exportOptionsPlist ExportOptions.plist "${AUTH[@]}" > "$OUT/export.log" 2>&1; then
  grep -E "error" "$OUT/export.log" | sort -u | head -10
  echo "Export failed (see $OUT/export.log). Nothing was uploaded."
  exit 1
fi
IPA="$(ls "$OUT"/export/*.ipa 2>/dev/null | head -1)"
[ -n "$IPA" ] || { echo "The export made no .ipa. Nothing was uploaded."; exit 1; }

if [ "$UPLOAD" = no ]; then
  echo "▸ built $IPA (not uploaded)"
  exit 0
fi

# ---- upload --------------------------------------------------------------------
echo "▸ uploading"
if ! xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER" > "$OUT/upload.log" 2>&1; then
  grep -iE "error" "$OUT/upload.log" | head -10
  echo "Upload failed (see $OUT/upload.log)."
  exit 1
fi
echo "✓ Shotlister $VERSION ($NEXT) is with Apple. It shows up in TestFlight in 5 to 15 minutes."
