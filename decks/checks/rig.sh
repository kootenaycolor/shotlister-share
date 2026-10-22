#!/bin/bash
# Start a local hub carrying one film with one deck, so the editor and the live
# page can be measured against each other. Local only — never the real bucket.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PORT="${PORT:-8931}"
STATE="$HERE/state"
# **A real deck can be put in the rig.** Point DATA at a folder holding the
# same files `seed.py` makes — deck.json, paper.json, page.html, front.json,
# manifest.json and the pictures — and it is used as it is, unseeded. That is
# how the Call Her Back bible's own sheets were photographed in the editor on
# 2026-09-07 without touching the real bucket.
GIVEN="${DATA:-}"
DATA="${DATA:-$HERE/data}"
FILM="${FILM:-01a02852ebb00198e46a252100000000}"
W="$ROOT/hub/node_modules/.bin/wrangler"

freeport() {
  local held; held=$(lsof -ti "tcp:$PORT" 2>/dev/null)
  [ -n "$held" ] && kill -9 $held 2>/dev/null
  for _ in $(seq 1 20); do lsof -ti "tcp:$PORT" >/dev/null 2>&1 || return 0; sleep 0.5; done
}

case "${1:-up}" in
stop) freeport; echo "stopped"; exit 0;;
esac

freeport
rm -rf "$STATE"; mkdir -p "$STATE"
[ -z "$GIVEN" ] && python3 "$HERE/seed.py" "$DATA" >/dev/null

"$ROOT/hub/build.sh" >/dev/null || { echo "the browser half would not build"; exit 1; }

put() { (cd "$ROOT/hub" && $W r2 object put "shotlister-preview/$1" --file "$2" --local --persist-to "$STATE" >/dev/null 2>&1); }

printf '{"format":1,"project":"%s","title":"Call Her Back","engine":"0.1.0"}' "$FILM" > "$DATA/manifest.json"
put "p/$FILM/manifest.json"            "$DATA/manifest.json"
put "p/$FILM/front.json"               "$DATA/front.json"
put "p/$FILM/decks/lookbook.json"      "$DATA/deck.json"
put "p/$FILM/pages/lookbook.html"      "$DATA/page.html"
put "p/$FILM/decks/lookbook.paper.json" "$DATA/paper.json"
[ -f "$DATA/paper.html" ] && put "p/$FILM/decks/lookbook.paper.html" "$DATA/paper.html"
for f in "$DATA"/*.pdf "$DATA"/*.png "$DATA"/*.jpg "$DATA"/*.ttf; do
  [ -f "$f" ] && put "p/$FILM/docs/$(basename "$f")" "$f"
done
echo "bucket seeded"

# **Detached from this shell on purpose.** Started as a plain background job
# the hub died the moment the shell that ran this script exited — which is
# every time an agent runs it — and the next check found nothing listening.
(cd "$ROOT/hub" && nohup $W dev --local --port "$PORT" --persist-to "$STATE" \
  --var ACCESS_TEAM:"" --var ACCESS_AUD:"" --var PRESS_HOST:"http://localhost:$PORT" >"$HERE/wrangler.log" 2>&1 &)

for _ in $(seq 1 40); do
  curl -fsS -m 4 "http://localhost:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS -m 4 "http://localhost:$PORT/health" >/dev/null 2>&1 || { echo "hub would not start"; tail -20 "$HERE/wrangler.log"; exit 1; }
curl -fsS "http://localhost:$PORT/f/$FILM/api/manifest?as=owner@example.com" | grep -q "Call Her Back" \
  || { echo "the hub on $PORT is not ours"; exit 1; }
echo "up on http://localhost:$PORT"
