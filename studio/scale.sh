#!/bin/bash
# **The scale, and nothing between its steps.**
#
# On 2026-09-08 the Mac app drew text at 42 different sizes, gaps at 30 and
# corners at 12 — sizes half a point apart, which nobody can see one at a time
# and everybody can see all at once. Every one of them was rounded to its
# nearest step in `Brand` (`Size`, `Icon`, the five `radius*`), ties going to
# whichever neighbour more of the app already used, so almost nothing moved.
#
# The steps only stay steps if something says so. This is that something.
# **Reach for the nearest one rather than a new number** — and if a screen
# genuinely needs a size the scale has not got, add it *here and in `Brand`*
# rather than writing it at the call site, so the next reader knows it was a
# decision.
#
# Usage: studio/scale.sh          (from the repo root)
set -u
cd "$(dirname "$0")/.."

SANS="8 10 11 13 15 20"
ICONS="8 10 11 13 16 20 24 30"
RADII="radiusSmall radiusChip radius radiusRow radiusLarge radiusCard"

# Relay.swift and StudioApp.swift carry no drawing worth the name; Theme.swift
# is where the scale is *defined*, so it is the one file allowed to say a
# number out loud.
FILES=$(ls studio/Sources/*.swift | grep -v Theme.swift)

bad=0
report() { echo "  $1"; bad=$((bad+1)); }

# ---- type ------------------------------------------------------------------
# **Including sizes wrapped in `Brand.type(…)`.** `Chip` hid 9.5 and 11.5
# inside one for two weeks: the sweep did not rewrite them and this did not
# see them, because both looked only for a digit straight after the bracket.
for face in sans mono; do
  while read -r hit; do
    [ -z "$hit" ] && continue
    size=$(echo "$hit" | sed -E "s/.*\.$face\((Brand\.type\()?([0-9.]+).*/\2/")
    case " $SANS " in *" $size "*) ;; *) report "$hit  — .$face($size) is not on the scale ($SANS)";; esac
  done <<< "$(grep -rnoE "\.$face\((Brand\.type\()?[0-9.]+" $FILES)"
done
# A ternary picks two sizes and only the first was ever read.
while read -r hit; do
  [ -z "$hit" ] && continue
  size=$(echo "$hit" | sed -E 's/.*: ([0-9.]+)$/\1/')
  case " $SANS " in *" $size "*) ;; *) report "$hit  — $size is not on the scale ($SANS)";; esac
done <<< "$(grep -rnoE "\.(sans|mono)\([a-zA-Z. ]+\? [0-9.]+ : [0-9.]+" $FILES)"

# ---- icons -----------------------------------------------------------------
while read -r hit; do
  [ -z "$hit" ] && continue
  size=$(echo "$hit" | sed -E "s/.*system\(size: ([0-9.]+).*/\1/")
  case " $ICONS " in *" $size "*) ;; *) report "$hit  — icon $size is not on the scale ($ICONS)";; esac
done <<< "$(grep -rnoE 'system\(size: [0-9.]+' $FILES)"

# ---- gaps: a 2pt grid ------------------------------------------------------
while read -r hit; do
  [ -z "$hit" ] && continue
  n=$(echo "$hit" | sed -E 's/.*(spacing: |\.padding\((\.[a-z]+, )?)([0-9]+).*/\3/')
  [ $((n % 2)) -eq 0 ] || report "$hit  — $n is off the 2pt grid"
done <<< "$(grep -rnoE '(spacing: |\.padding\((\.[a-z]+, )?)[0-9]+\)?' $FILES | grep -E '[0-9]+\)?$')"

# ---- corners: the five Brand names, never a number -------------------------
while read -r hit; do
  [ -z "$hit" ] && continue
  report "$hit  — a corner is one of Brand's five ($RADII), not a number"
done <<< "$(grep -rnE 'cornerRadius: [0-9]' $FILES)"

if [ "$bad" -eq 0 ]; then
  echo "scale: clean — every size, gap and corner is on the scale"
else
  echo
  echo "scale: $bad off the scale"
  exit 1
fi
