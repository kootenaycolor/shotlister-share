#!/bin/bash
# What the next version could be, for the dialog in `Release Shotlister.app`.
#
# Prints four lines: the last released version, the small-fixes number, the
# new-features number, and how many changes have landed since. Nothing else, so
# the AppleScript can read it by line and not parse anything.
#
#   0.3.0
#   0.3.1
#   0.4.0
#   2
#
# **The tags are the truth, not `release/VERSION`.** A tag exists only because
# `release.sh` finished and published; the file is just where the chosen number
# is put on the way in. Reading the file instead would offer 0.4.0 twice if a
# release failed after the file was written and before the tag was made.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

# -v:refname orders 0.10.0 after 0.9.0; plain sort does not.
LAST="$(git -C "$ROOT" tag --sort=-v:refname | grep -m1 '^v[0-9]' | sed 's/^v//' || true)"

if [ -z "$LAST" ]; then
  # Nothing has ever been released. Whatever the file says is the starting point.
  LAST="$(cat VERSION 2>/dev/null || echo 0.0.0)"
  COUNT="$(git -C "$ROOT" rev-list --count HEAD)"
else
  COUNT="$(git -C "$ROOT" rev-list --count "v$LAST..HEAD")"
fi

MAJOR="${LAST%%.*}"
REST="${LAST#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"

# A version with something odd in it (a suffix, a missing part) would otherwise
# produce a nonsense next number and publish under it.
case "$MAJOR$MINOR$PATCH" in
  *[!0-9]*|"") echo "release/VERSION or the last tag is not three numbers: $LAST" >&2; exit 1 ;;
esac

echo "$LAST"
echo "$MAJOR.$MINOR.$((PATCH + 1))"
echo "$MAJOR.$((MINOR + 1)).0"
echo "$COUNT"
