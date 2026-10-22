#!/bin/bash
# What the phone cannot be allowed to get wrong.
#
# Runs the phone's own decoder over his real projects, and exercises writing on
# scratch copies. Read-only against anything of his, and it launches nothing —
# so unlike the Mac's battery it cannot disturb him whatever he is doing.

set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(cd .. && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
( cd "$ROOT/ffi" && cargo build --release --offline --quiet )

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -O -target arm64-apple-macos14.0 \
  -import-objc-header "$ROOT/ffi/include/shotlister.h" \
  Sources/Engine.swift Sources/Kind.swift Sources/Scan.swift Sources/ScriptPage.swift \
  Sources/Location.swift Sources/Relay.swift Sources/DiagramBeats.swift \
  "$ROOT/shared/FileNames.swift" "$ROOT/shared/RelayCarrier.swift" "$ROOT/shared/Offload.swift" "$ROOT/shared/ProjectTypes.swift" "$ROOT/shared/ExportPresets.swift" "$ROOT/shared/BoardPlan.swift" Checks/main.swift \
  "$ROOT/ffi/target/release/libshotlister_ffi.a" \
  -o "$OUT/checks"

"$OUT/checks"

echo
echo "── copy, against the law in CLAUDE.md ──"
../tools/check-copy.sh

# ---- the half that has to run on a phone ------------------------------------
#
# Anything drawn — a photograph being shrunk — needs UIKit, and UIKit needs a
# simulator. It uses whichever one is already booted rather than starting one,
# so the battery stays quick; if none is, it says so instead of passing quietly.

echo
echo "How much a photograph weighs"
BOOTED=$(xcrun simctl list devices booted | grep -c Booted || true)
if [ "$BOOTED" -eq 0 ]; then
  echo "  · skipped — no simulator running (open one and run this again)"
else
  SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  xcrun -sdk iphonesimulator swiftc -O -target arm64-apple-ios17.0-simulator -sdk "$SDK" \
    Sources/Media.swift Sources/Moving.swift Sources/Kind.swift Sources/DocumentRich.swift "$ROOT/shared/ClipEncoder.swift" \
    Checks/pictures/main.swift -o "$OUT/pictures"
  xcrun simctl spawn booted "$OUT/pictures"
fi

# ---- the export page follows Auto ---------------------------------------------
#
# His report, 2026-10-17: on Auto, moving Size or picking the paper left the
# page as it was. The screen asked its shelf of drawn pages first, with a key
# made from the plan in hand — the old one — so the old page came back. This
# builds the app, opens the export on a copy of the fixture (`--exportsheet`)
# and makes each change in turn (`--exportthen`); every one must draw the
# page again. `SIM=<udid>` picks the simulator; another booted one otherwise.
echo
echo "The export page follows Auto"
SIM="${SIM:-$(xcrun simctl list devices booted | grep -oE '\(([0-9A-F-]{36})\)' | head -1 | tr -d '()')}"
if [ -z "$SIM" ]; then
  echo "  · skipped — no simulator running (open one and run this again)"
else
  ( cd "$ROOT/ffi" && cargo build --release --target aarch64-apple-ios-sim --quiet 2>/dev/null )
  xcodegen generate --spec project.yml >/dev/null
  xcodebuild -project Shotlister.xcodeproj -scheme Shotlister -configuration Debug \
    -derivedDataPath build -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    CODE_SIGN_IDENTITY="-" build >"$OUT/build.log" 2>&1 || { grep -E "error:" "$OUT/build.log" | head; exit 1; }
  xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Shotlister.app
  DOCS="$(xcrun simctl get_app_container "$SIM" com.example.shotlister.phone data)/Documents"
  rm -rf "$DOCS/ZZ Export Follow.shotlist" "$DOCS/export-preview.txt"
  cp -R "$ROOT/studio/fixtures/Daybreak.shotlist" "$DOCS/ZZ Export Follow.shotlist"
  STEPS="autosize=0.7|autosize=1.3|autopaper=portrait|autopaper=landscape|off=description|on=description|layout=manual"
  xcrun simctl launch --terminate-running-process "$SIM" com.example.shotlister.phone \
    -ExportCheck --exportsheet "ZZ Export Follow" \
    --exportset "layout=auto;autosize=1;autopaper=auto" --exportthen "$STEPS" >/dev/null
  for _ in $(seq 1 60); do sleep 2; [ -f "$DOCS/export-preview.txt" ] && break; done
  xcrun simctl terminate "$SIM" com.example.shotlister.phone 2>/dev/null || true
  said="$(cat "$DOCS/export-preview.txt" 2>/dev/null || true)"
  rm -rf "$DOCS/ZZ Export Follow.shotlist" "$DOCS/export-preview.txt"
  bad=0
  for step in autosize=0.7 autosize=1.3 autopaper=landscape off=description on=description; do
    line="$(echo "$said" | grep "^$step " | head -1)"
    if echo "$line" | grep -q "redrawn yes .*layout auto"; then
      printf '  ✓  %s\n' "Auto, $step: the page is drawn again and the table stays on Auto"
    else
      bad=1; printf '  ✗  %s  (%s)\n' "Auto, $step: the page is drawn again" "${line:-nothing said}"
    fi
  done
  if echo "$said" | grep -q "^layout=manual .*layout manual"; then
    printf '  ✓  %s\n' "Manual is reached only by picking it"
  else
    bad=1; printf '  ✗  %s\n' "Manual is reached only by picking it"
  fi
  [ "$bad" = 0 ] || exit 1
fi
