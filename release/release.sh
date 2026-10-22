#!/bin/bash
# Cuts a release of Shotlister Studio: builds it, gets Apple's stamp on it, and
# puts it where his other Mac will find it.
#
#   release/release.sh              cut and publish release/VERSION
#   release/release.sh --dry-run    everything except talking to Apple or GitHub
#
# Driven by double-clicking `Release Shotlister.app` at the root. Nothing in
# here is meant to be typed by Nathaniel.
#
# **The order of operations is not arbitrary and must not be tidied.** An app is
# signed, then notarised, then stapled — and the stapled copy is what gets
# zipped for the updater and put in the disk image. Zipping before stapling
# ships an app that has Apple's approval on Apple's servers and no proof of it
# in the bundle, which works on a Mac that is online and fails on one that is
# not.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
HERE="$ROOT/release"

# **Run from a double-click, not a terminal.** A GUI launch never reads
# .zshrc — its PATH is the bare system one: `/usr/gnu/bin:/usr/local/bin:/bin:
# /usr/bin:.`, confirmed on this Mac, and missing three directories real tools
# in this script live in. `gh` and `cargo` are under Homebrew; `spctl` — the
# Gatekeeper check partway through a real release — is in `/usr/sbin`, which
# is *not* on that bare PATH either and is easy to miss because every other
# tool here (codesign, xcrun, ditto, hdiutil, git) happens to sit in the one
# directory (`/usr/bin`) that bare PATH does have. Without this line the first
# check reports "gh is missing" on a Mac where gh plainly is not, and a run
# that gets further dies invisibly at the Gatekeeper check instead — "command
# not found" from a plain `spctl ...` on its own line aborts the script under
# `set -e` with no die message, which is exactly what happened the first time
# this ran for real: exit 0 reported, everything after stapling simply absent.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:/usr/sbin:/sbin:$PATH"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

VERSION="$(cat "$HERE/VERSION")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
APP_NAME="Shotlister Studio"
BUNDLE_ID="com.example.shotlister.studio"
REPO="YOUR_GITHUB_USER/shotlister-releases"
NOTARY_PROFILE="shotlister-notary"
# Apple sign-in for notarising: the saved keychain profile when this session can
# see it, else the API key file named in ~/.config/release-notary/notary.env
# (NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER), so a release can run unattended.
NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
if ! xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 && [ -f "$HOME/.config/release-notary/notary.env" ]; then
  . "$HOME/.config/release-notary/notary.env"
  NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
fi

STAGE="$HERE/staging"
OUT="$HERE/out"
APP="$STAGE/$APP_NAME.app"
ZIP="$OUT/Shotlister-Studio-$VERSION.zip"
DMG="$OUT/Shotlister-Studio-$VERSION.dmg"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------- preflight
#
# Everything that can be known before a minute of building is spent is checked
# here. A release that fails after notarisation has cost ten minutes and left
# half-published state behind; one that fails in this block has cost nothing.

say "→ checking what this needs"

IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
[ -n "$IDENTITY" ] || die \
"No Developer ID Application certificate on this Mac.

An Apple Development certificate signs an app for your own machines only; a Mac
that did not build the app will refuse it. Make the other kind once, in Xcode:

  Settings → Accounts → your account → Manage Certificates → + →
  Developer ID Application

then run this again."

command -v gh >/dev/null || die "The GitHub command line tool is missing."

if [ "$DRY" = "0" ]; then
  xcrun notarytool history "${NOTARY_AUTH[@]}" >/dev/null 2>&1 || die \
"This Mac cannot talk to Apple's notary service yet.

Double-click 'Set Up Releasing.app' in the Apps folder once and follow it."
fi

git -C "$ROOT" rev-parse "v$VERSION" >/dev/null 2>&1 && die \
"v$VERSION has already been released. Put a newer number in release/VERSION."

echo "  identity   $IDENTITY"
echo "  version    $VERSION (build $BUILD_NUMBER)"

# ---------------------------------------------------------------- the build
#
# Built into release/staging, never into build/. `studio/build.sh` opens with
# `rm -rf` on whatever it is pointed at, three or four threads share this one
# checkout, and both batteries drive the bundle in build/ — a release that
# builds there takes the app away from a run in progress and reads as a
# catastrophe. Ref 331 cost one run 79 false failures exactly that way.

say "→ building $APP_NAME $VERSION"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
SHOTLISTER_BUILD="$APP" \
SHOTLISTER_SIGN="$IDENTITY" \
SHOTLISTER_UPDATES=1 \
  "$ROOT/studio/build.sh" > "$OUT/build.log" 2>&1 \
  || { tail -40 "$OUT/build.log"; die "The build failed. Its output is above."; }

[ -x "$APP/Contents/MacOS/ShotlisterStudio" ] || die "The build produced no program."

say "→ checking the signature"
codesign --verify --deep --strict "$APP" || die "The signature does not hold together."
# Captured into a variable and matched with bash's own `[[ ... ]]`, not piped
# into `grep -q`. `grep -q` exits the moment it finds a match, which closes its
# end of the pipe — and under `pipefail` (on, above), codesign then dying of
# SIGPIPE while it was still writing later lines makes the *whole check* read
# as failed, even though the flag was right there. It was: this exact line
# reported the hardened runtime missing from a signature that had it, the
# first time this script ran for real. No process, no pipe, no SIGPIPE.
CODESIGN_INFO="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ "$CODESIGN_INFO" == *"flags="*"runtime"* ]] \
  || die "The hardened runtime is missing — Apple will refuse to notarise this."

if [ "$DRY" = "1" ]; then
  say "→ dry run: stopping before Apple and GitHub"
  echo "  $APP"
  exit 0
fi

# ----------------------------------------------------------- Apple's stamp
#
# Notarisation is Apple looking inside the app and saying it found nothing
# malicious. Without it the first launch on his other Mac is a dialogue saying
# the app cannot be opened, with no obvious way past it.

say "→ sending it to Apple (this takes a few minutes)"
NOTARIZE_ZIP="$OUT/notarize.zip"
rm -f "$NOTARIZE_ZIP"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  "${NOTARY_AUTH[@]}" --wait --timeout 30m \
  || die "Apple refused it. 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE' says why."
rm -f "$NOTARIZE_ZIP"

say "→ stapling Apple's answer into the app"
xcrun stapler staple "$APP"

# The real test, and the one worth believing: this is the question macOS itself
# asks when he double-clicks it on a Mac that has never seen it. Captured
# rather than piped into `grep -q`, for the same SIGPIPE-under-pipefail reason
# as the signature check above — `tee | grep -q` has the identical failure
# mode, just with one more process in the chain to get killed by it.
GATEKEEPER_INFO="$(spctl -a -vvv -t install "$APP" 2>&1)"
printf '%s\n' "$GATEKEEPER_INFO" > "$OUT/gatekeeper.txt"
[[ "$GATEKEEPER_INFO" == *"accepted"* ]] \
  || die "Gatekeeper would reject this app. Not publishing it."
[[ "$GATEKEEPER_INFO" == *"Notarized Developer ID"* ]] \
  || die "Gatekeeper accepted it but not as notarised. Not publishing it."
echo "  accepted, notarised"

# ------------------------------------------------------- what gets published
#
# Two files, because they do different jobs. The zip is what the updater
# downloads and swaps in; the disk image is what a person opens the first time,
# with the Applications folder sitting beside the app to drag it into.

say "→ packing"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

DMGROOT="$OUT/dmgroot"
rm -rf "$DMGROOT"; mkdir -p "$DMGROOT"
cp -R "$APP" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMGROOT" \
  -ov -format UDZO "$DMG"
rm -rf "$DMGROOT"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" "${NOTARY_AUTH[@]}" --wait --timeout 30m \
  || die "Apple refused the disk image."
xcrun stapler staple "$DMG"

# ------------------------------------------------------------- the feed entry
#
# `sign_update` signs the zip with the private key that lives in his keychain
# and nowhere else. Sparkle on the other Mac checks that signature against the
# public key baked into the app, which is what stops anything but this Mac from
# handing his laptop a "new version".

say "→ signing the download"
SIG_LINE="$("$HERE/vendor/bin/sign_update" "$ZIP")"
echo "  $SIG_LINE"

say "→ writing the feed"
FEED_DIR="$OUT/shotlister-releases"
if [ ! -d "$FEED_DIR" ]; then
  gh repo clone "$REPO" "$FEED_DIR" -- --quiet 2>/dev/null || die \
    "Cannot reach the downloads repository $REPO."
fi
git -C "$FEED_DIR" pull --quiet

NOTES="$(git -C "$ROOT" log --format='%s' \
  "$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || echo HEAD~20)"..HEAD \
  2>/dev/null | sed 's/^/<li>/;s/$/<\/li>/' || echo '<li>Improvements.</li>')"

# Plain-English notes written by hand, when the caller supplies them.
[ -z "${RELEASE_NOTES_FILE:-}" ] && [ -f "$HERE/notes-$VERSION.html" ] && RELEASE_NOTES_FILE="$HERE/notes-$VERSION.html"
if [ -n "${RELEASE_NOTES_FILE:-}" ]; then NOTES="$(cat "$RELEASE_NOTES_FILE")"; fi

python3 "$HERE/appcast.py" \
  --feed "$FEED_DIR/appcast.xml" \
  --version "$VERSION" \
  --build "$BUILD_NUMBER" \
  --url "https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")" \
  --signature "$SIG_LINE" \
  --notes "$NOTES"

git -C "$FEED_DIR" add appcast.xml
git -C "$FEED_DIR" commit -qm "Shotlister Studio $VERSION"
git -C "$FEED_DIR" push --quiet

say "→ publishing"
gh release create "v$VERSION" "$ZIP" "$DMG" \
  --repo "$REPO" --title "Shotlister Studio $VERSION" \
  --notes "$(echo "$NOTES" | sed 's/<[^>]*>//g')"

git -C "$ROOT" tag "v$VERSION"

say "✓ Shotlister Studio $VERSION is out"
echo "  First install:  https://github.com/$REPO/releases/latest"
echo "  Everyone already running it will be offered it automatically."
