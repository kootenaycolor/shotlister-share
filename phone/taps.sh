#!/bin/bash
# **The half of checking that presses things.**
#
# checks.sh runs the phone's decoder over his real projects and draws nothing;
# --film and --shotpage open any screen for a photograph. Neither can press a
# button, which is how the Shot mark once shipped looking right and doing
# nothing. These press them, on whichever simulator is booted.
#
#   ./phone/taps.sh
#
# It works on the simulator's own copy of Call Her Back and puts every shot it
# marks back the way it found it.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

SIM=$(xcrun simctl list devices booted | grep -oE '\(([0-9A-F-]{36})\)' | head -1 | tr -d '()')
[ -n "$SIM" ] || { echo "no simulator running — open one and run this again"; exit 1; }

xcodegen generate --spec project.yml >/dev/null
xcodebuild -project Shotlister.xcodeproj -scheme Shotlister -configuration Debug \
  -derivedDataPath build -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIM" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_ENTITLEMENTS=Shotlister.entitlements test 2>&1 \
  | grep -E "Test Case.*(passed|failed)|error:" || true
