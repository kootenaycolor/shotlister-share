#!/bin/bash
# Builds Shotlister for iPhone and puts it on the phone.
#
# The Mac app is two compiles and a folder. The phone cannot be, because signing
# a build onto a real device is Xcode's machinery and nobody else's — so this
# script drives Xcode rather than replacing it. What it does not do is ask you to
# remember any of it: double-click "Install on iPhone" and this runs.
#
#   ./build.sh            build and install on the connected iPhone
#   ./build.sh --sim      build and install on the booted simulator instead

set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(cd .. && pwd)"
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

SIM=no
[ "${1:-}" = "--sim" ] && SIM=yes

# ---- the engine, cross-compiled ------------------------------------------
# Rust needs the iOS standard library, which is a separate download. Adding a
# target that is already there is a no-op, so this is safe to run every time.
echo "→ engine (iOS)"
if [ "$SIM" = yes ]; then
  TARGET=aarch64-apple-ios-sim
else
  TARGET=aarch64-apple-ios
fi
rustup target add "$TARGET" >/dev/null 2>&1 || true
( cd "$ROOT/ffi" && cargo build --release --target "$TARGET" --quiet )

LIB="$ROOT/ffi/target/$TARGET/release/libshotlister_ffi.a"
[ -f "$LIB" ] || { echo "engine did not build"; exit 1; }

# ---- the Xcode project, generated ----------------------------------------
# project.yml is the readable source; the .xcodeproj is build output. Regenerated
# every time so a new Swift file never needs adding to anything by hand.
echo "→ project"
command -v xcodegen >/dev/null || { echo "xcodegen is missing — brew install xcodegen"; exit 1; }
xcodegen generate --spec project.yml >/dev/null

# ---- the app --------------------------------------------------------------
# Quiet when it works, and *loud about the reason* when it does not. Sending
# xcodebuild to /dev/null once turned a Swift compile error into silence.
build_quietly() {
  local log
  log="$(mktemp)"
  if ! xcodebuild -project Shotlister.xcodeproj -scheme Shotlister \
        -configuration Debug -derivedDataPath build "$@" build >"$log" 2>&1; then
    echo
    grep -E "error:" "$log" | sed "s|$PWD/||" | sort -u | head -20
    echo
    echo "build failed — see $log"
    exit 1
  fi
  rm -f "$log"
}

echo "→ app"
if [ "$SIM" = yes ]; then
  # **Signed, even here.** `CODE_SIGNING_ALLOWED=NO` is the usual simulator
  # shortcut and it silently drops the entitlements file with the signature —
  # so the Keychain refuses every write and sync cannot be set up, in the
  # simulator only. Ad-hoc signing costs nothing and keeps the simulator
  # honest about what the phone will do.
  build_quietly -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_ENTITLEMENTS=Shotlister.entitlements PROVISIONING_PROFILE_SPECIFIER=""
  APP="build/Build/Products/Debug-iphonesimulator/Shotlister.app"
  # SHOTLISTER_SIM=<udid>: that simulator only. With several booted (two
  # threads at once), "booted" lands on whichever simctl picks.
  DEV="${SHOTLISTER_SIM:-booted}"
  xcrun simctl install "$DEV" "$APP"
  xcrun simctl launch "$DEV" com.example.shotlister.phone >/dev/null
  echo "✓ running in the simulator"
  exit 0
fi

build_quietly -sdk iphoneos -destination 'generic/platform=iOS' -allowProvisioningUpdates
APP="build/Build/Products/Debug-iphoneos/Shotlister.app"

# ---- onto the phone -------------------------------------------------------
# Named rather than identified by number, so this keeps working after a restore
# or a new phone.
# Note the `grep -v unavailable` — "unavailable" contains "available", and
# matching on the wrong one hands the installer a phone that is not there.
# The `|| true` is load-bearing. With no phone on the list every grep in the
# chain finds nothing and exits 1, and under `pipefail` that killed the whole
# script one line before the message explaining what to do — so plugging in
# nothing produced a build that stopped dead and said nothing at all.
# **Since Xcode 27 the list carries simulators too**, marked `simulated` in
# a last column, and a real phone's identifier is `00008140-…`, not a UUID —
# so the old UUID match picked a simulator and the install said the device
# could not install apps. A real, paired, available phone: not simulated.
DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | grep -i iphone | grep -v unavailable | grep -v simulated \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{4,}' \
  | head -1 || true)

if [ -z "$DEVICE" ]; then
  echo "No iPhone is connected and unlocked."
  echo "Plug it in, unlock it, and run this again."
  exit 2
fi

echo "→ installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
echo "✓ Shotlister is on your iPhone"
