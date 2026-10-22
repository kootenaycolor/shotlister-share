#!/bin/bash
# **The Film Set Objects pack, into the bucket the portal serves it from.**
#
# The browser's engine is built without the pack's pictures (feature
# `fso-art`, off in `web/`), so a plan on the Diagrams page asks for
# `fso/<id>.png` beside the film and the worker answers it from the bucket's
# `fso/` — one copy for every film, behind each film's own door (Ref 1216).
#
#   hub/fso.sh                      the live bucket, only when the pack changed
#   hub/fso.sh --local DIR          a local bucket (serve.sh, the checks)
#
# **The live copy is only rewritten when the pack changed**: a fingerprint of
# every file's name and size is kept beside it (`fso/.set`) and compared first,
# so a deploy that did not touch the pack costs one small read.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PACK="$(cd "$HERE/../engine/assets/fso" && pwd)"
W="$HERE/node_modules/.bin/wrangler"
[ -x "$W" ] || W="npx --yes wrangler@4"

if [ "${1:-}" = "--local" ]; then
  STATE="$2"
  # All of it, sixteen at a time: a plan draws pack pictures its film never
  # names (a camera's body, a person's pose), so a subset would show holes.
  ls "$PACK"/*.png | xargs -P 16 -I{} sh -c 'cd "$1" && "$2" r2 object put "shotlister-preview/fso/$(basename "$3")" --file "$3" --content-type image/png --local --persist-to "$4" </dev/null >/dev/null 2>&1' _ "$HERE" "$W" {} "$STATE"
  echo "  $(ls "$PACK"/*.png | wc -l | tr -d ' ') pack pictures"
  exit 0
fi

set_now=$(cd "$PACK" && ls -l *.png | awk '{print $5, $NF}' | shasum | cut -c1-16)
set_live=$(cd "$HERE" && $W r2 object get "shotlister/fso/.set" --pipe --remote 2>/dev/null)
if [ "$set_live" = "$set_now" ]; then
  echo "hub: the pack is current"
  exit 0
fi
echo "hub: putting the Film Set Objects pack in the bucket ($(ls "$PACK"/*.png | wc -l | tr -d ' ') pictures)"
fail=0
for f in "$PACK"/*.png; do
  (cd "$HERE" && $W r2 object put "shotlister/fso/$(basename "$f")" --file "$f" \
    --content-type image/png --remote </dev/null >/dev/null 2>&1) || fail=$((fail+1))
done
if [ $fail -gt 0 ]; then
  echo "hub: $fail pack pictures would not go up — run this again"
  exit 1
fi
printf '%s' "$set_now" > "${TMPDIR:-/tmp}/fso-set"
(cd "$HERE" && $W r2 object put "shotlister/fso/.set" --file "${TMPDIR:-/tmp}/fso-set" --remote </dev/null >/dev/null 2>&1)
echo "hub: the pack is up"
