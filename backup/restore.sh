#!/bin/bash
# **Getting a film back as it was on a particular day.**
#
# A backup nobody has ever restored is theatre, so this is the other half of
# `backup.sh` and it is meant to be run for real rather than admired.
#
# **It never touches the film he is working in.** The restored copy lands on the
# Desktop under its own name — `Call Her Back (31 Aug).shotlist` — so the two can
# be opened side by side and compared before anything is decided. Overwriting
# the live film is not a thing this can do, on purpose: the whole point of a
# backup is to be sure, and a restore that clobbers is a second way to lose
# work.
#
# **The photographs come from the live film**, copied in if it is still there.
# They are not in the backup (see `backup.sh` for why), they are content-
# addressed so an extra one is harmless, and anything genuinely missing comes
# down from the relay on the Sync button.

#
# **By name, for the Projects Console** — 2026-09-15. Nothing is asked and
# nothing is typed; the answer is one line on stdout:
#
#     backup/restore.sh --list "Call Her Back"        one line per backup, newest first:
#                                                     backup: "Call Her Back"  2026-09-15-1412  "/…/2026-09-15-1412.zip"
#     backup/restore.sh "Call Her Back"               the newest one:
#                                                     restored: "Call Her Back"  from 2026-09-15-1412  to "/Users/…/Desktop/Call Her Back (15 Sep).shotlist"
#     backup/restore.sh "Call Her Back" 2026-09-14-1300   that one
#
# Same landing place, same rule — the Desktop, never the live film. A name or a
# stamp nobody has ends with status 1 and `refused: …`.

set -uo pipefail

FILMS="${SHOTLISTER_FILMS:-$HOME/Documents/Shotlister}"
INTO="${SHOTLISTER_BACKUPS:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister Backups}"
DESKTOP="${SHOTLISTER_DESKTOP:-$HOME/Desktop}"

say()  { printf '%s\n' "$1"; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }
oops() { printf '\033[31m%s\033[0m\n' "$1"; }

# ---- the console's way in: a name, no questions ------------------------------
#
# Unpacking is the same as below, in a function so the two roads cannot drift.
# The pictures come across the same way too.
unpack() { # unpack <zip> <film name> — sets $target, or returns 1
  local zip="$1" film="$2"
  local stamp when label n scratch inner
  stamp=$(basename "$zip" .zip)
  when=$(echo "$stamp" | cut -d- -f1-3)
  label=$(date -j -f "%Y-%m-%d" "$when" "+%-d %b" 2>/dev/null || echo "$when")
  target="$DESKTOP/$film ($label).shotlist"
  n=2
  while [ -e "$target" ]; do target="$DESKTOP/$film ($label) $n.shotlist"; n=$((n + 1)); done
  scratch=$(mktemp -d)
  if ! ditto -x -k "$zip" "$scratch" 2>/dev/null; then rm -rf "$scratch"; return 1; fi
  inner=$(find "$scratch" -maxdepth 2 -name "*.shotlist" -type d | head -1)
  [ -n "$inner" ] || { rm -rf "$scratch"; return 1; }
  mv "$inner" "$target"
  rm -rf "$scratch"
  live="$FILMS/$film.shotlist/media"
  [ -d "$live" ] && cp -R "$live" "$target/media" 2>/dev/null
  return 0
}

# The film's backup folder, by name, case blind.
folder_named() { # folder_named <name> — prints the folder, or nothing
  local wanted
  wanted=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  for folder in "$INTO"/*/; do
    [ -d "$folder" ] || continue
    if [ "$(printf '%s' "$(basename "$folder")" | tr '[:upper:]' '[:lower:]')" = "$wanted" ]; then
      printf '%s' "${folder%/}"; return 0
    fi
  done
  return 0
}

if [ "${1:-}" = "--list" ] && [ -n "${2:-}" ]; then
  folder=$(folder_named "$2")
  [ -n "$folder" ] || { printf 'refused: no backups of "%s"\n' "$2"; exit 1; }
  name=$(basename "$folder")
  ls -1 "$folder"/*.zip 2>/dev/null | sort -r | while IFS= read -r zip; do
    printf 'backup: "%s"  %s  "%s"\n' "$name" "$(basename "$zip" .zip)" "$zip"
  done
  exit 0
fi

if [ -n "${1:-}" ]; then
  folder=$(folder_named "$1")
  [ -n "$folder" ] || { printf 'refused: no backups of "%s"\n' "$1"; exit 1; }
  name=$(basename "$folder")
  if [ -n "${2:-}" ]; then
    zip="$folder/$2.zip"
    [ -f "$zip" ] || { printf 'refused: no backup of "%s" stamped %s\n' "$name" "$2"; exit 1; }
  else
    zip=$(ls -1 "$folder"/*.zip 2>/dev/null | sort | tail -1)
    [ -n "$zip" ] || { printf 'refused: no backups of "%s"\n' "$name"; exit 1; }
  fi
  if unpack "$zip" "$name"; then
    printf 'restored: "%s"  from %s  to "%s"\n' "$name" "$(basename "$zip" .zip)" "$target"
    exit 0
  fi
  printf 'refused: the backup %s of "%s" could not be opened\n' "$(basename "$zip" .zip)" "$name"
  exit 1
fi

# ---- the hand's way in: a list and a number ----------------------------------

[ -d "$INTO" ] || { oops "There are no backups yet. Double-click \"Back Up Films\" first."; exit 1; }

# **A plain loop, not `mapfile`.** macOS ships bash 3.2 and has since 2007 —
# `mapfile` arrived in bash 4 and is simply not there, so the script died on its
# own first line with "command not found" and then a cascade of unbound
# variables. Anything written for bash on this Mac has to be 3.2.
zips=()
while IFS= read -r line; do
  zips+=("$line")
done < <(find "$INTO" -name "*.zip" 2>/dev/null | sort -r)
[ "${#zips[@]}" -gt 0 ] || { oops "There are no backups yet. Double-click \"Back Up Films\" first."; exit 1; }

bold ""
bold "Which one do you want back?"
say ""
i=1
for zip in "${zips[@]}"; do
  film=$(basename "$(dirname "$zip")")
  stamp=$(basename "$zip" .zip)
  when=$(echo "$stamp" | cut -d- -f1-3)
  at=$(echo "$stamp" | cut -d- -f4)
  pretty=$(date -j -f "%Y-%m-%d" "$when" "+%a %-d %b %Y" 2>/dev/null || echo "$when")
  printf "  %2d. %-18s %s at %s:%s   (%s)\n" "$i" "$film" "$pretty" "${at:0:2}" "${at:2:2}" "$(du -h "$zip" | cut -f1)"
  i=$((i + 1))
done
say ""
printf "Type a number and press return (or just press return to stop): "
read -r pick
[ -n "$pick" ] || { say "Nothing restored."; exit 0; }
case "$pick" in (*[!0-9]*|"") oops "That is not one of the numbers."; exit 1;; esac
[ "$pick" -ge 1 ] && [ "$pick" -le "${#zips[@]}" ] || { oops "That is not one of the numbers."; exit 1; }

zip="${zips[$((pick - 1))]}"
film=$(basename "$(dirname "$zip")")
stamp=$(basename "$zip" .zip)
when=$(echo "$stamp" | cut -d- -f1-3)
label=$(date -j -f "%Y-%m-%d" "$when" "+%-d %b" 2>/dev/null || echo "$when")

target="$DESKTOP/$film ($label).shotlist"
n=2
while [ -e "$target" ]; do target="$DESKTOP/$film ($label) $n.shotlist"; n=$((n + 1)); done

scratch=$(mktemp -d)
if ! ditto -x -k "$zip" "$scratch" 2>/dev/null; then
  oops "That backup could not be opened."
  rm -rf "$scratch"; exit 1
fi

inner=$(find "$scratch" -maxdepth 2 -name "*.shotlist" -type d | head -1)
[ -n "$inner" ] || { oops "That backup does not look like a film."; rm -rf "$scratch"; exit 1; }

mv "$inner" "$target"
rm -rf "$scratch"

# The pictures, from the film he is working in. Same bytes under the same names,
# so this can only ever add.
live="$FILMS/$film.shotlist/media"
if [ -d "$live" ]; then
  cp -R "$live" "$target/media" 2>/dev/null
  say ""
  say "Pictures copied across from the film you are working in."
else
  say ""
  say "No pictures copied — press Sync once it is open and they will come down."
fi

say ""
bold "Restored to your Desktop:"
say "  $(basename "$target")"
say ""
say "Open it from Shotlister with Open other… — it is a separate film, so the"
say "one you are working in has not been touched."
open -R "$target" 2>/dev/null || true
