#!/bin/bash
# Turning the Drive bridge on and off.
#
# A launchd agent of its own, deliberately separate from anything else he runs:
# it is not behind the ◉ menu and it is not part of the projects console. His
# instruction. It answers to nothing but this script.

set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="com.example.shotlister.drivebridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/shotlister-drivebridge.log"
REPO="$(pwd)"

case "${1:-status}" in

install)
  mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <!-- The bundle's own binary, not an interpreter running a script. Full Disk
       Access is granted to a bundle; launching it any other way would attribute
       the file reads to whatever ran it and the grant would not apply. -->
  <key>ProgramArguments</key>
  <array>
    <string>$REPO/bridge/Shotlister Drive Sync.app/Contents/MacOS/drivesync</string>
    <string>--apply</string>
    <string>--quiet</string>
  </array>
  <!-- **Every fifteen seconds**, because a settled run costs ten milliseconds
       — measured, with the engine loaded — and five minutes was a number picked
       out of caution rather than out of what it costs. -->
  <key>StartInterval</key><integer>15</integer>
  <!-- And immediately when either side is touched. launchd only notices a
       folder's own contents changing, not a change deep inside it, so this
       catches the common cases at once and the timer catches the rest. -->
  <key>WatchPaths</key>
  <array>
    <string>$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister</string>
    <string>$HOME/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/cinematography/projects</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$PLIST"
  echo "on"
  ;;

remove)
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "off"
  ;;

status)
  if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    echo "on"
  else
    echo "off"
  fi
  ;;

log)
  [ -f "$LOG" ] && tail -40 "$LOG" || echo "(nothing logged yet)"
  ;;

*)
  echo "usage: agent.sh [install|remove|status|log]" >&2
  exit 2
  ;;
esac
