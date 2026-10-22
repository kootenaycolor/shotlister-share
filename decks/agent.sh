#!/bin/bash
# Turning the press on and off.
#
# His plan of 2026-09-05: the deck lives on the portal and **his Mac is the
# press**, because a beautiful PDF wants his real typefaces and a real browser.
# This is what makes that automatic — when a deck is changed in the editor, the
# Mac notices, prints it, and puts the PDF back under the film's Documents
# without him pressing anything.
#
# A launchd agent of its own, the same shape as the Drive bridge's. It answers
# to nothing but this script.
#
# The catch, stated plainly: the Mac has to be on. A deck changed while it is
# shut prints the next time it wakes, not before.

set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.example.shotlister.deckpress"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/shotlister-deckpress.log"
HERE="$(pwd)"

case "${1:-status}" in

install)
  mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <!-- The bundle's own binary, not an interpreter running the script. Full
       Disk Access is granted to a bundle, and the press has to read his Drive
       folder; run as python3 under launchd it died on "Operation not
       permitted" the first time it was tried (2026-09-07). -->
  <key>ProgramArguments</key>
  <array>
    <string>$HERE/Shotlister Deck Press.app/Contents/MacOS/deckpress</string>
    <string>--once</string>
    <string>--quiet</string>
  </array>
  <!-- **Every three minutes, not every fifteen seconds.** The bridge polls a
       folder on this Mac; this one asks the portal over the network and, when
       something has changed, spends minutes in headless Chrome. A deck is
       changed a few times an hour at most, and a PDF that is three minutes
       behind is not behind. -->
  <key>StartInterval</key><integer>180</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <!-- Printing is heavy and nothing waits on it. Let his own work go first. -->
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST
  [ -x "$HERE/Shotlister Deck Press.app/Contents/MacOS/deckpress" ] || ./press/build.sh >/dev/null
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$PLIST"
  echo "on"
  echo "One-time step, if it has never been done: System Settings > Privacy & Security >"
  echo "Full Disk Access > + > Developer/shotlister/decks/Shotlister Deck Press"
  ;;

remove)
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "off"
  ;;

status)
  if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then echo "on"; else echo "off"; fi
  ;;

log)
  [ -f "$LOG" ] && tail -40 "$LOG" || echo "(nothing printed yet)"
  ;;

once)
  /usr/bin/python3 "$HERE/tools/press.py" --once
  ;;

*)
  echo "usage: agent.sh [install|remove|status|log|once]" >&2
  exit 2
  ;;
esac
