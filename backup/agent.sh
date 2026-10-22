#!/bin/bash
# **Asks macOS to take a backup every day.** Run once, by double-clicking
# *Set Up Automatic Backups*; running it again is harmless and just replaces
# what is already there.
#
# `StartCalendarInterval` rather than `StartInterval`, on purpose: a laptop is
# asleep most of the day, and launchd runs a missed calendar job as soon as the
# machine wakes. An interval job would simply not fire.
#
# It never asks for a password and never touches anything outside his own
# LaunchAgents folder — this is the same shape as `bridge/agent.sh`.

set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

LABEL="com.example.shotlister.backup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS="$HOME/Library/Logs/Shotlister"

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
oops() { printf '\n\033[31m%s\033[0m\n' "$1"; }

mkdir -p "$HOME/Library/LaunchAgents" "$LOGS"

say "Setting up the daily backup…"

# Unload an older one first, or `bootstrap` refuses and the new plist is ignored
# while the old one goes on running — which reads as "my change did nothing".
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$REPO/backup/backup.sh</string>
	</array>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key><integer>13</integer>
		<key>Minute</key><integer>0</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$LOGS/backup.log</string>
	<key>StandardErrorPath</key>
	<string>$LOGS/backup.log</string>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
PLIST

if ! launchctl bootstrap "gui/$UID" "$PLIST" 2>/dev/null; then
  oops "macOS would not take the schedule."
  echo "The backup still works by hand — double-click \"Back Up Films\"."
  exit 1
fi

# **Prove it rather than announce it.** A schedule that was accepted and is not
# listed is the failure worth catching, and it is silent otherwise.
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  echo "Done. Your films back themselves up every day at 1pm,"
  echo "and as soon as the Mac wakes if it was asleep then."
  echo
  echo "Taking one now, so there is something there straight away…"
  echo
  "$REPO/backup/backup.sh"
else
  oops "It was accepted but is not listed, which should not happen."
  echo "The backup still works by hand — double-click \"Back Up Films\"."
  exit 1
fi
