#!/bin/bash
# **The portal, on this Mac, with his real film in it — to look at, not to check.**
#
# `checks.sh` seeds a two-line film and asks the worker questions over curl;
# `scans.mjs` and `offline.mjs` seed his film and read the screen through a
# headless browser. Neither leaves a hub running for a person to open. This
# one does: it puts *Call Her Back* — the change logs, the real portal card and
# every record page off the live bucket, and as many pictures as you ask for —
# into a throwaway local bucket, starts the hub, prints the addresses, and
# stays up until you stop it.
#
#     hub/serve.sh              # the film's page and its four app modes
#     PICTURES=80 hub/serve.sh  # with the first eighty pictures
#     PORT=8797 hub/serve.sh    # on a port of your own
#
# **Nothing here writes to the real bucket.** The card and pages are read with
# `r2 object get --remote`, which needs a Cloudflare sign-in; without one the
# hub still runs and the record pages simply say what an empty card says.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8796}"
PICTURES="${PICTURES:-40}"
FILM="${FILM:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister/Call Her Back.shotlist}"
WHO="owner@example.com"
W="$HERE/node_modules/.bin/wrangler"
STATE="$(mktemp -d /tmp/serve-state-XXXX)"
BOX="$(mktemp -d /tmp/serve-box-XXXX)"

[ -x "$W" ] || { echo "run npm install in hub/ first"; exit 1; }
[ -d "$FILM/changes" ] || { echo "no film at $FILM — set FILM to one"; exit 1; }

# The relay id is the portal's address for the film, and it is in the film.
ID=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['project'])" "$FILM/remote.json")

put() { # put <key> <file>
  # **`</dev/null`**: wrangler reads stdin, and inside a loop it swallowed the
  # rest of the list — a film came up with one change log and one picture.
  (cd "$HERE" && "$W" r2 object put "shotlister-preview/$1" --file "$2" --local --persist-to "$STATE" </dev/null >/dev/null 2>&1)
}
pull() { # pull <key> <file> — read-only off the live bucket
  (cd "$HERE" && "$W" r2 object get "shotlister/$1" --pipe --remote > "$2" 2>/dev/null) && [ -s "$2" ]
}

cleanup() {
  # The wrangler first, gently, so it takes its workerd with it; then whatever
  # still holds the port. Killing by port alone leaves the wrangler parent
  # behind — the cause of Ref 930.
  pkill -TERM -f "wrangler.*dev --local --port $PORT" 2>/dev/null
  sleep 1
  pkill -9 -f "wrangler.*dev --local --port $PORT" 2>/dev/null
  lsof -ti "tcp:$PORT" 2>/dev/null | xargs kill -9 2>/dev/null
  rm -rf "$STATE" "$BOX"
}
trap cleanup EXIT INT TERM

echo "Building the browser half…"
"$HERE/build.sh" >/dev/null || { echo "the browser half would not build"; exit 1; }

echo "Putting $(basename "$FILM") in a local bucket…"
put "p/$ID/manifest.json" "$FILM/manifest.json"
n=0
for f in "$FILM"/changes/*.log; do put "p/$ID/logs/$(basename "$f")" "$f"; n=$((n+1)); done
echo "  $n change logs"

# The Film Set Objects pictures its plans stand on (Ref 1216).
"$HERE/fso.sh" --local "$STATE"

n=0
for f in "$FILM"/media/proxies/*; do
  [ "$n" -ge "$PICTURES" ] && break
  put "p/$ID/media/$(basename "$f")" "$f"; n=$((n+1))
done
echo "  $n pictures"

echo "Reading the card and the pages off the live bucket…"
if pull "p/$ID/front.json" "$BOX/front.json"; then
  put "p/$ID/front.json" "$BOX/front.json"
  echo "  the card"
  for slug in $(python3 - "$BOX/front.json" <<'EOF'
import json,sys
c=json.load(open(sys.argv[1]))
seen=set()
for g in c.get('groups',[]):
    for r in g.get('rows',[]): seen.add(r)
for p in c.get('pages',[]): seen.add(p.get('slug',''))
print(' '.join(s for s in seen if s))
EOF
  ); do
    if pull "p/$ID/pages/$slug.json" "$BOX/$slug.json"; then
      put "p/$ID/pages/$slug.json" "$BOX/$slug.json"; echo "  page: $slug"
    fi
  done
  for k in cover.png; do
    pull "p/$ID/media/$k" "$BOX/$k" && put "p/$ID/media/$k" "$BOX/$k"
  done
else
  echo "  (not signed in to Cloudflare — the record pages will be empty)"
fi

echo "Starting the hub on $PORT…"
lsof -ti "tcp:$PORT" 2>/dev/null | xargs kill -9 2>/dev/null
(cd "$HERE" && "$W" dev --local --port "$PORT" --persist-to "$STATE" \
  --var ACCESS_TEAM:"" --var ACCESS_AUD:"" >"$STATE/wrangler.log" 2>&1) &
for _ in $(seq 1 60); do
  curl -fsS -m 4 "http://localhost:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS -m 4 "http://localhost:$PORT/health" >/dev/null 2>&1 || { echo "the hub would not start — see $STATE/wrangler.log"; exit 1; }

echo
# 127.0.0.1, not localhost: a share-link check may have left an `HttpOnly`
# `hubkey` cookie on localhost that turns you into a link holder (403).
echo "  film      http://127.0.0.1:$PORT/f/$ID?as=$WHO"
echo "  shot list http://127.0.0.1:$PORT/f/$ID/shotlist?as=$WHO"
echo "  locations http://127.0.0.1:$PORT/f/$ID/locations?as=$WHO"
echo "  boards    http://127.0.0.1:$PORT/f/$ID/boards?as=$WHO"
echo "  schedule  http://127.0.0.1:$PORT/f/$ID/schedule?as=$WHO"
echo "  diagrams  http://127.0.0.1:$PORT/f/$ID/diagrams?as=$WHO"
echo
echo "Stop it with ctrl-C."
wait
