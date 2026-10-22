#!/bin/bash
# One-time setup so this Mac can cut releases. Driven by double-clicking
# `Set Up Releasing.app`; every question it asks is a dialogue, not a prompt.
#
# **No password is typed anywhere, here or ever.** Apple offers two ways to
# prove who you are to the notary service: an app-specific password, or a key
# file downloaded from App Store Connect. This uses the key file. He picks it in
# a normal Open dialogue, `notarytool` puts it in the keychain, and nothing has
# to be read out, pasted into a chat, or remembered.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
PROFILE="shotlister-notary"
HERE_VENDOR="$ROOT/release/vendor/bin"

note() { osascript -e "display dialog \"$1\" with title \"Set up releasing\" buttons {\"OK\"} default button \"OK\" with icon note" >/dev/null; }
stop() { osascript -e "display dialog \"$1\" with title \"Set up releasing\" buttons {\"OK\"} default button \"OK\" with icon stop" >/dev/null; exit 1; }

# ------------------------------------------------------- 1. the certificate
IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"

if [ -z "$IDENTITY" ]; then
  CHOICE="$(osascript -e 'display dialog "This Mac has no Developer ID certificate yet.

That is the one that lets an app run on a Mac that did not build it. Make it once, in Xcode:

   Settings → Accounts → your account →
   Manage Certificates → + → Developer ID Application

Then run this again." with title "Set up releasing" buttons {"Later", "Open Xcode"} default button "Open Xcode" with icon caution' \
    -e 'button returned of result' 2>/dev/null || echo Later)"
  [ "$CHOICE" = "Open Xcode" ] && open -a Xcode || true
  exit 1
fi

# ------------------------------------------------------------ 2. the key file
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  note "This Mac is already set up to release.

Certificate: $IDENTITY

Nothing to do — double-click 'Release Shotlister' whenever you want a new version out."
  exit 0
fi

note "Two things to fetch from Apple, once.

1. Go to appstoreconnect.apple.com → Users and Access → Integrations → Keys
2. Make a key with the Developer role and download the file it gives you.
   It downloads only once, so keep it somewhere safe.

Then click OK and pick that file."

KEYFILE="$(osascript -e 'POSIX path of (choose file with prompt "Pick the key file you downloaded from Apple (it ends in .p8)" of type {"p8", "public.data"})' 2>/dev/null || true)"
[ -n "$KEYFILE" ] || exit 1
[ -f "$KEYFILE" ] || stop "That file is not there any more."

# The file is named AuthKey_XXXXXXXXXX.p8, and those ten characters are the key
# id Apple wants — so he does not have to go and look it up.
GUESS="$(basename "$KEYFILE" | sed -n 's/^AuthKey_\(.*\)\.p8$/\1/p')"

KEYID="$(osascript -e "display dialog \"The key's ID — Apple shows it beside the key in that same list.\" default answer \"$GUESS\" with title \"Set up releasing\" buttons {\"OK\"} default button \"OK\"" -e 'text returned of result' 2>/dev/null || true)"
[ -n "$KEYID" ] || exit 1

ISSUER="$(osascript -e 'display dialog "The Issuer ID — the long code at the top of that same page on Apple'"'"'s site." default answer "" with title "Set up releasing" buttons {"OK"} default button "OK"' -e 'text returned of result' 2>/dev/null || true)"
[ -n "$ISSUER" ] || exit 1

# --------------------------------------------------------- 3. into the keychain
if ! OUT="$(xcrun notarytool store-credentials "$PROFILE" \
      --key "$KEYFILE" --key-id "$KEYID" --issuer "$ISSUER" 2>&1)"; then
  stop "Apple did not accept that.

$(echo "$OUT" | tail -3)"
fi

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || stop "The details were saved but Apple still will not talk to this Mac."

# ------------------------------------------------- 4. the keychain, warmed up
#
# The key that signs each download lives in the keychain, and the first time
# anything reads it macOS puts up an "allow access?" dialogue. Left alone, that
# dialogue appears eight minutes into a release, behind whatever he is doing —
# and if the Mac happens to be locked it appears behind the lock screen, where
# it stops the release dead with no visible reason. Better to provoke it here,
# once, while he is already answering dialogues. Click **Always Allow**.
note "One last dialogue: macOS is about to ask whether this may use the update signing key.

Click 'Always Allow' — otherwise it asks again in the middle of every release."

WARM="$(mktemp -d)/warm.zip"
printf 'warm' > "${WARM%.zip}.txt"
( cd "$(dirname "$WARM")" && zip -q warm.zip warm.txt )
"$HERE_VENDOR/sign_update" "$WARM" >/dev/null 2>&1 || true
rm -rf "$(dirname "$WARM")"

note "Done — this Mac can release Shotlister now.

Certificate: $IDENTITY

You will not be asked any of this again. Double-click 'Release Shotlister' whenever a new version should go out."
