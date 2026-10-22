#!/bin/bash
# Builds Shotlister Studio.app — Rust engine inside, Swift outside.
#
# Same shape as app/build.sh, and for the same reason: the whole thing is two
# compiles and a folder, and a script you can read beats a project file you
# cannot. Double-clickable when it finishes.
#
# **This script builds both the everyday app and the released one.** The only
# differences a release makes are handed in as environment: a real signing
# identity, the hardened runtime and a feed to check. Everything else — the
# same sources, the same engine, the same bundle — is identical, on purpose. A
# release built by a second, parallel script is a release nobody has tested.
#
#   SHOTLISTER_BUILD    where the bundle lands
#   SHOTLISTER_SIGN     signing identity; "-" (ad-hoc) unless release.sh says otherwise
#   SHOTLISTER_UPDATES  1 to embed Sparkle and the update feed

set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(cd .. && pwd)"
# **Where the bundle lands, overridable** — `SHOTLISTER_BUILD=/somewhere/My.app`.
#
# Both batteries already take `SHOTLISTER_APP` so a run can drive a bundle
# nobody else will delete mid-run, and `STATUS.md` has told people to do that
# since Ref 331 cost a run 79 false failures. It was advice nobody could
# follow: this line was hardcoded, so there was no way to *make* a bundle of
# your own to point it at. Two full batteries were thrown away on 2026-08-23
# for exactly that — one read 18 passed, 153 failed and the next 0 passed, 171
# failed, both of them another thread rebuilding underneath the run.
# **The Labs flavour — `SHOTLISTER_FLAVOUR=labs`.** His instruction,
# 2026-09-14: *"build this out in a LABS fork but keep the working build up
# and running here."* The same sources, the same engine, a different app:
# **Shotlister Labs**, its own bundle identifier so macOS treats it as a
# second program, its own films folder (`Documents/Shotlister Labs`) so it
# can never open a real film by accident, and `-DSHOTLISTER_LABS` so the app
# knows which one it is and says so in its top bar. The everyday build is
# untouched by this: leave the variable unset and nothing here changes.
# **In the Labs checkout, a build is always Labs** — his rule, 2026-09-28:
# *"when you are working labs fork, always build in the same place:
# build/Shotlister Labs.app."* The flavour defaulted to studio everywhere, so a
# plain `./studio/build.sh` here made a *Studio*-flavoured app (his real films
# folder, no LABS badge) and a thread copied it over his Labs by hand. Here the
# checkout itself decides: no setting to forget.
if [ "$(basename "$ROOT")" = "shotlister-labs" ]; then
  FLAVOUR="labs"
else
  FLAVOUR="${SHOTLISTER_FLAVOUR:-studio}"
fi
if [ "$FLAVOUR" = "labs" ]; then
  APP_NAME="Shotlister Labs"
  BUNDLE_ID="com.example.shotlister.labs"
  FLAVOUR_FLAGS=(-DSHOTLISTER_LABS)
else
  APP_NAME="Shotlister Studio"
  BUNDLE_ID="com.example.shotlister.studio"
  FLAVOUR_FLAGS=()
fi
APP="${SHOTLISTER_BUILD:-$ROOT/build/$APP_NAME.app}"
export PATH="$HOME/.cargo/bin:$PATH"

# **Signed with his own Developer ID, even for a plain build.**
#
# It was ad-hoc (`-`), and ad-hoc is not an identity: the signature *is* the
# hash of that exact binary, so every rebuild is, to macOS, a different program.
# That is invisible until something asks the system to remember a decision
# about this app — and the Keychain does.
#
# The relay password lives there, and clicking **Always Allow** writes down the
# app that was allowed. Ad-hoc, what gets written down is one build's hash, and
# the next build is a stranger again. His login keychain had **nine** of them
# stacked up by 2026-08-31, one per "Always Allow", and it asked him every
# single time. Signed properly it writes `teamid:YOURTEAMID` instead, which
# every future build still matches.
#
# `release/release.sh` passes its own identity in and is unaffected. The
# fallback stays ad-hoc so a machine without his certificate can still build.
#
# **The cost, measured the same day, so nobody rediscovers it:** a signed app is
# one LaunchServices knows, and macOS brings one of those to the front at launch
# in a way it never bothered to for an ad-hoc binary. `studio/quick.sh` went
# from **0 focus trips to 10** on the same 15 checks — nothing fails, the app
# hands the front straight back, but it flickers, and it flickers while he is
# working. Trying to refuse it does not work: `.accessory` stops SwiftUI making
# a window at all, and deactivating at launch was tried and changed nothing.
# **`SHOTLISTER_SIGN=- ./studio/build.sh` is the way back to a quiet battery**,
# at the price of the Keychain asking again.
if [ -z "${SHOTLISTER_SIGN:-}" ] \
   && security find-identity -v -p codesigning 2>/dev/null \
      | grep -q "Developer ID Application: YOUR NAME"; then
  SHOTLISTER_SIGN="Developer ID Application: YOUR NAME (YOURTEAMID)"
  # A plain build is not a release: no timestamp (it is a network round trip
  # per signature, and a build should work on a train) and no hardened runtime.
  # Neither has anything to do with having a stable identity, which is the only
  # thing being bought here.
  : "${SHOTLISTER_HARDEN:=0}"
fi
SIGN="${SHOTLISTER_SIGN:--}"
HARDEN="${SHOTLISTER_HARDEN:-1}"
UPDATES="${SHOTLISTER_UPDATES:-0}"

# **The version, in two numbers, and neither of them typed here.**
#
# Both were the literal string `0.1` until 2026-08-24, hardcoded inside a
# quoted heredoc, which meant every build the app had ever made claimed to be
# the same version as every other. That is invisible while the only copy is the
# one on this Mac, and fatal the moment a second Mac has to decide whether what
# it just downloaded is newer than what it is running.
#
#   CFBundleShortVersionString  the one he reads: release/VERSION
#   CFBundleVersion             the one Sparkle compares: how many commits deep
#                               this is, which only ever goes up
VERSION="$(cat "$ROOT/release/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

echo "→ engine"
( cd "$ROOT/ffi" && cargo build --release --offline --quiet )

# A thread building beside another can keep its own compiled engine
# (`CARGO_TARGET_DIR`), so neither swaps the library out mid-link.
LIB="${CARGO_TARGET_DIR:-$ROOT/ffi/target}/release/libshotlister_ffi.a"
[ -f "$LIB" ] || { echo "engine did not build"; exit 1; }

echo "→ app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ---------------------------------------------------------------- the updater
#
# Sparkle goes in by hand, because this build is `swiftc` and a folder and is
# staying that way. Copied rather than referenced so the bundle that leaves
# this Mac carries its own copy.
#
# **The XPC services come straight back out.** They exist so a *sandboxed* app
# can reach the network and the filesystem to install an update. This app is
# not sandboxed and never will be — `ARCHITECTURE.html` §11 rules the Mac App
# Store out precisely because sandboxing fights arbitrary folders and a local
# MCP — and every one of them is a nested program that would have to be signed
# and notarised for nothing.
SPARKLE_FLAGS=()
if [ "$UPDATES" = "1" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$ROOT/release/vendor/Sparkle.framework" "$APP/Contents/Frameworks/"
  rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
  # ...and the top-level symlink that pointed at them, or the bundle ships a
  # link to nothing. codesign accepts a dangling symlink without a word and
  # Apple's notary service does not.
  rm -f  "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
  SPARKLE_FLAGS=(
    -F "$APP/Contents/Frameworks"
    -framework Sparkle
    -DSHOTLISTER_UPDATES
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks
  )
fi

# ------------------------------------------------------------------- the icon
#
# Two files, because the icon is a Liquid Glass one and those are new. macOS 26
# reads `Assets.car` and lights the artwork itself; macOS 14 and 15 know nothing
# about that and fall back to `Shotlister.icns`. Both are built from the same
# Icon Composer document by release/icon/build-icon.sh — never edited by hand.
#
# A missing icon is not an error here. The everyday build should still work in a
# checkout where the icon has not been compiled yet.
for f in Shotlister.icns Assets.car; do
  [ -f "$ROOT/release/$f" ] && cp "$ROOT/release/$f" "$APP/Contents/Resources/$f"
done

# ------------------------------------------------------------------- the plist
#
# Unquoted heredoc — the version numbers above are interpolated. Nothing else
# in here may contain a bare `$`.
{
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>ShotlisterStudio</string>
  <key>CFBundleIconFile</key><string>Shotlister</string>
  <key>CFBundleIconName</key><string>Shotlister</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
    <key>CFBundleURLSchemes</key><array><string>shotlister</string></array>
  </dict></array>
PLIST
if [ "$UPDATES" = "1" ]; then
cat <<PLIST
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/YOUR_GITHUB_USER/shotlister-releases/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>YOUR_SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
PLIST
fi
cat <<'PLIST'
</dict>
</plist>
PLIST
} > "$APP/Contents/Info.plist"

swiftc \
  -O \
  -target arm64-apple-macos14.0 \
  -import-objc-header "$ROOT/ffi/include/shotlister.h" \
  -parse-as-library \
  Sources/*.swift \
  ../shared/*.swift \
  "$LIB" \
  -framework SwiftUI -framework AppKit -framework WebKit -framework PDFKit \
  -framework AVKit -framework AVFoundation -framework ScreenCaptureKit \
  ${SPARKLE_FLAGS[@]+"${SPARKLE_FLAGS[@]}"} \
  ${FLAVOUR_FLAGS[@]+"${FLAVOUR_FLAGS[@]}"} \
  -o "$APP/Contents/MacOS/ShotlisterStudio"

# ---------------------------------------------------------------- the signature
#
# **A failed signature is no longer swallowed.** This line ended in
# `2>/dev/null || true` until 2026-08-24, which was survivable while the
# signature was ad-hoc and only this Mac ever ran the result: an unsigned app
# still launches here. It stops being survivable the moment the app is meant to
# open on a Mac that did not build it, where an unsigned or half-signed bundle
# does not launch at all — and the failure would have been printed nowhere.
#
# Nested code is signed first and the app last. A signature seals what is
# inside it, so signing the wrapper before its contents seals a stale hash and
# the bundle is refused on the machine that matters.
sign() {
  local what="$1"
  if [ "$SIGN" = "-" ]; then
    codesign --force --sign - "$what"
  elif [ "$HARDEN" = "1" ]; then
    codesign --force --sign "$SIGN" --timestamp --options runtime \
      --entitlements "$ROOT/release/Shotlister.entitlements" "$what"
  else
    # A real identity, but a build rather than a release. Same certificate, so
    # the same designated requirement — which is the whole point — without the
    # network round trip and the hardened runtime a shipped copy needs.
    codesign --force --sign "$SIGN" --timestamp=none \
      --entitlements "$ROOT/release/Shotlister.entitlements" "$what"
  fi
}

if [ "$UPDATES" = "1" ]; then
  F="$APP/Contents/Frameworks/Sparkle.framework"
  sign "$F/Versions/B/Updater.app"
  sign "$F/Versions/B/Autoupdate"
  sign "$F"
fi
sign "$APP"

echo "✓ $APP  ($VERSION, build $BUILD_NUMBER)"
