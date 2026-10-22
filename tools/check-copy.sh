#!/bin/bash
# Flags UI copy that reads like narration instead of a label — the rule in
# CLAUDE.md under "How the app talks". Not a pass/fail gate: judging the
# exception clause (what a delete costs, a device limitation, a warning, a
# first-run instruction) takes a person or a thread reading it, not a script.
# This just makes sure nothing slides past unread. Called from studio/quick.sh
# and phone/checks.sh, so it runs every time either battery does.
#
# A literal is skipped if the line right above it is a comment — the
# convention threads have already started using on purpose (see
# LocationDetailView.swift, MediaGallery.swift) is to justify a kept sentence
# in a comment right above it. That comment is itself the review; no need to
# flag it again on every run.
set -uo pipefail
cd "$(dirname "$0")/.."

DIRS="studio/Sources phone/Sources app/Sources"
THRESHOLD=46
OUT="$(mktemp -t check-copy)"

for dir in $DIRS; do
  [ -d "$dir" ] || continue
  for file in "$dir"/*.swift; do
    [ -f "$file" ] || continue
    awk -v file="$file" -v threshold="$THRESHOLD" '
      function trimmed(s) { gsub(/^[ \t]+/, "", s); return s }
      {
        line = $0
        t = trimmed(line)
        is_comment = (t ~ /^\/\//)
        if (is_comment) { prev_comment = 1; next }
        if (match(line, /(Text|Button|TextField|\.help)\("[^"]+"/)) {
          s = substr(line, RSTART, RLENGTH)
          sub(/^(Text|Button|TextField|\.help)\("/, "", s)
          sub(/"$/, "", s)
          # Drop one level of string interpolation before measuring — a
          # numeric or short-value \(...) should not count toward "too long",
          # only the words actually written around it.
          gsub(/\\\([^()]*\)/, "#", s)
          if (length(s) >= threshold && !prev_comment) {
            printf "%s:%d: %s\n", file, NR, t
          }
        }
        prev_comment = 0
      }
    ' "$file"
  done
done | tee "$OUT"

count=$(wc -l < "$OUT" | tr -d ' ')
rm -f "$OUT"
if [ "$count" -eq 0 ]; then
  echo "  no long copy found in studio/, phone/, or app/"
else
  echo "  $count line(s) — read each against the exception clause in CLAUDE.md"
  echo "  (a label names the thing; a sentence earns its place or it comes out)"
fi
