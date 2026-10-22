#!/bin/bash
# **Point-in-time copies of every film, so a mistake is undoable.**
#
# His ask, 2026-08-31: *"can we create a backup system so nothing is lost? that
# could store in icloud drive"*.
#
# ## Why this exists when there is already a relay and iCloud
#
# **Neither of those is a backup.** They are both *sync*, and sync is the exact
# opposite of what is wanted here: delete a scene by accident and both of them
# dutifully carry the deletion to every device within seconds. There is nothing
# to go back to. What is missing is not another copy of *now* — it is a copy of
# *last Tuesday*.
#
# ## What is in a snapshot, and what is deliberately not
#
# **The change logs and the manifest. That is the whole film.** Every shot,
# every scene, every edit ever made, and the order they happened in — the engine
# rebuilds the entire project from these. All three of his films together come
# to about 1.8 MB of them, so a snapshot costs almost nothing and he can keep
# months of them.
#
# **Not the photographs**, and that is a decision rather than an omission:
#
# - They already exist in three places — this Mac, iCloud, and the relay, which
#   never deletes a picture because a picture is written once under the hash of
#   its own contents.
# - They are 483 MB against the list's 1.8 MB, so including them would make
#   every snapshot 270 times bigger for the part that is least at risk.
# - **And his disk is at 99%** (17 GB free of 926, measured 2026-08-31). A
#   backup system that quietly eats the last of it is not a kindness.
#
# So: this protects the irreplaceable half. A restored film opens complete, with
# its pictures drawn from wherever they already are.
#
# ## How long they are kept
#
# Everything from the last fortnight, then one a week for three months, then one
# a month. Recent mistakes are the ones you notice late; a year-old film needs a
# landmark, not a diary.
#
# ## One film, for the Projects Console
#
#     backup/backup.sh "Call Her Back"
#
# The console's door, 2026-09-15: the same snapshot, of that one film, and one
# line the console can read back on stdout —
#
#     backed up: "Call Her Back"  at "/…/Shotlister Backups/Call Her Back/2026-09-15-1412.zip"
#     unchanged: "Call Her Back"  at "/…/Shotlister Backups/Call Her Back/2026-09-14-1300.zip"
#     refused: no film called "Nope"
#
# `unchanged` names the newest zip already on file, which is the backup that
# stands for now. A name nobody has ends with status 1. The tidy-up runs
# either way; it only ever thins what a newer one already covers.

set -uo pipefail

FILMS="${SHOTLISTER_FILMS:-$HOME/Documents/Shotlister}"
INTO="${SHOTLISTER_BACKUPS:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister Backups}"
STAMP=$(date "+%Y-%m-%d-%H%M")
TODAY=$(date "+%Y-%m-%d")

say()  { printf '%s\n' "$1"; }
oops() { printf '\033[31m%s\033[0m\n' "$1"; }

if [ ! -d "$FILMS" ]; then
  oops "No films folder at $FILMS"
  exit 1
fi

mkdir -p "$INTO" || { oops "Could not make $INTO"; exit 1; }

# A note beside the backups, for the day he finds this folder and wonders.
# Written every run so it cannot drift from what the script actually does.
cat > "$INTO/What these are.txt" <<'NOTE'
Shotlister backups
==================

One zip per film per run. Each holds that film's complete history — every shot,
every scene, every edit ever made — as of the moment it was taken.

Photographs are NOT in here, on purpose. They already live in three places (this
Mac, iCloud, and your sync relay, which never deletes one), and they are three
hundred times the size of the list. Keeping them here would fill your disk to
protect the part that is least at risk.

TO GO BACK TO AN OLDER VERSION
------------------------------
Double-click "Restore a Film" at the top of the Shotlister folder in Developer.
It lists what is here and puts the one you pick on your Desktop, ready to open.

Nothing here is ever overwritten and nothing is deleted except by the tidy-up,
which keeps: everything from the last fortnight, one a week for three months,
and one a month after that.
NOTE

# **One film, by name.** Case blind, since the console's name for a film and
# the folder's can differ in that one way and be the same film.
ONLY="${1:-}"
if [ -n "$ONLY" ]; then
  found=""
  for film in "$FILMS"/*.shotlist; do
    [ -d "$film" ] || continue
    if [ "$(printf '%s' "$(basename "$film" .shotlist)" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$ONLY" | tr '[:upper:]' '[:lower:]')" ]; then
      found="$film"; break
    fi
  done
  if [ -z "$found" ]; then
    printf 'refused: no film called "%s"\n' "$ONLY"
    exit 1
  fi
  FILMS_TO_DO=("$found")
else
  FILMS_TO_DO=("$FILMS"/*.shotlist)
fi

made=0
for film in "${FILMS_TO_DO[@]}"; do
  [ -d "$film" ] || continue
  name=$(basename "$film" .shotlist)
  [ -d "$film/changes" ] || {
    say "  · $name — nothing to back up yet"
    [ -n "$ONLY" ] && printf 'refused: "%s" has nothing to back up yet\n' "$name" && exit 1
    continue
  }

  mkdir -p "$INTO/$name"
  target="$INTO/$name/$STAMP.zip"

  # **Skip an identical one.** Opening the app rewrites nothing, so running this
  # twice in an afternoon should not leave two files that are the same bytes.
  # Compared on the logs' own names and sizes, which is what changes when the
  # film does.
  fingerprint=$(cd "$film" && find changes -type f -exec stat -f "%N %z" {} \; 2>/dev/null | sort | shasum | cut -d' ' -f1)
  # Hidden, because this folder is one he opens in Finder and a fingerprint
  # beside every backup reads as clutter he has to learn to ignore.
  last=$(ls -1 "$INTO/$name"/.seen-* 2>/dev/null | tail -1)
  if [ -n "$last" ] && [ "$(cat "$last" 2>/dev/null)" = "$fingerprint" ]; then
    say "  · $name — unchanged since the last one"
    if [ -n "$ONLY" ]; then
      newest=$(ls -1 "$INTO/$name"/*.zip 2>/dev/null | sort | tail -1)
      printf 'unchanged: "%s"  at "%s"\n' "$name" "$newest"
    fi
    continue
  fi

  # Built in a scratch folder and moved in, so an interrupted run never leaves
  # half a zip looking like a backup.
  scratch=$(mktemp -d)
  mkdir -p "$scratch/$name.shotlist"
  cp "$film/manifest.json" "$scratch/$name.shotlist/" 2>/dev/null
  cp -R "$film/changes" "$scratch/$name.shotlist/" 2>/dev/null
  # `remote.json` travels too: a restored film should still know its relay.
  cp "$film/remote.json" "$scratch/$name.shotlist/" 2>/dev/null

  if ditto -c -k --sequesterRsrc --keepParent "$scratch/$name.shotlist" "$scratch/out.zip" 2>/dev/null; then
    mv "$scratch/out.zip" "$target"
    printf '%s' "$fingerprint" > "$INTO/$name/.seen-$STAMP"
    size=$(du -h "$target" | cut -f1)
    say "  ✓ $name — $size"
    [ -n "$ONLY" ] && printf 'backed up: "%s"  at "%s"\n' "$name" "$target"
    made=$((made + 1))
  else
    oops "  ✗ $name — could not be packed"
    if [ -n "$ONLY" ]; then
      printf 'refused: "%s" could not be packed\n' "$name"
      rm -rf "$scratch"
      exit 1
    fi
  fi
  rm -rf "$scratch"
done

# ---- the tidy-up ---------------------------------------------------------
#
# Keep everything from the last fortnight; then one a week out to three months;
# then one a month. **Never the newest of anything** — the rule only ever thins
# what is already covered by something newer in the same period.

fortnight=$(date -v-14d "+%Y-%m-%d")
quarter=$(date -v-90d "+%Y-%m-%d")

for folder in "$INTO"/*/; do
  [ -d "$folder" ] || continue
  seen_week=""
  seen_month=""
  # **`while read`, never `for x in $(ls …)`.** His films are called things like
  # *Call Her Back*, so every path here has spaces in it — and an unquoted `$(ls)`
  # in a `for` splits each one into pieces. The loop then ran over fragments,
  # `basename` returned "Not", no date ever parsed, and **the tidy-up silently
  # kept all 365 of a year's backups**. It reported success the whole time.
  # Caught 2026-08-31 by giving it a fake year and counting what survived.
  while IFS= read -r zip; do
    [ -n "$zip" ] || continue
    stamp=$(basename "$zip" .zip)
    day=$(echo "$stamp" | cut -d- -f1-3)
    # Inside the fortnight: keep everything, no question.
    if [[ "$day" > "$fortnight" || "$day" == "$fortnight" ]]; then continue; fi

    if [[ "$day" > "$quarter" ]]; then
      week=$(date -j -f "%Y-%m-%d" "$day" "+%Y-%V" 2>/dev/null)
      if [ "$week" = "$seen_week" ]; then rm -f "$zip" "$folder.seen-$stamp"; else seen_week="$week"; fi
    else
      month=$(echo "$day" | cut -d- -f1-2)
      if [ "$month" = "$seen_month" ]; then rm -f "$zip" "$folder.seen-$stamp"; else seen_month="$month"; fi
    fi
  done < <(ls -1 "$folder"*.zip 2>/dev/null | sort -r)
done

kept=$(find "$INTO" -name "*.zip" 2>/dev/null | wc -l | tr -d ' ')
total=$(du -sh "$INTO" 2>/dev/null | cut -f1)
say ""
if [ "$made" -eq 0 ]; then
  say "Nothing had changed. $kept backup(s) on file, $total."
else
  say "$made new. $kept backup(s) on file, $total."
fi
say "They are in: $INTO"

# **The portal's own files too, on the daily run only** (2026-10-04). Who is
# invited, the share links, What Viewers See, the written pages, documents and
# boards lived only in the bucket. `portal.sh` keeps a never-delete mirror and a
# dated copy of the small files in "Shotlister Portal Backups". Not on a
# one-film run: the console reads that run's single line on stdout.
if [ -z "$ONLY" ]; then
  bash "$(dirname "$0")/portal.sh" || say "The portal backup did not finish this time — the films above are fine."
fi
