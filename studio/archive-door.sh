#!/bin/bash
# The Projects Console's archive door, end to end, on throwaway everything.
#
#   studio/archive-door.sh
#
# `--archivefilm <page>` / `--unarchivefilm <page>` (`FilmDoor.swift`): one
# film, found by the Notion page it is linked to, into Shotlister's bin and off
# the relay — and back. This plays the whole of it against the **real relay
# code running on this Mac** (`wrangler dev`, a throwaway bucket, the same way
# `relay/checks.sh` does) with scratch films in a scratch folder
# (`SHOTLISTER_FILMS`) linked to a page id that is nobody's project. Nothing
# here reaches the internet, his relay, his Keychain or his films.
#
# Needs a built app (`studio/build.sh`); `SHOTLISTER_APP` picks another.

set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

[ -x /opt/homebrew/bin/node ] && export PATH="/opt/homebrew/bin:$PATH"

APP="${SHOTLISTER_APP:-$ROOT/build/Shotlister Studio.app/Contents/MacOS/ShotlisterStudio}"
[ -x "$APP" ] || { echo "no app at $APP — run studio/build.sh first"; exit 1; }

PORT=${PORT:-8797}
RELAY="http://127.0.0.1:$PORT"
BASE="$RELAY/v1"
TOKEN="checking-token-not-a-secret"
SCRATCH=$(mktemp -d)
FILMS="$SCRATCH/films"
# Not a real project: 32 hex characters no Notion page has.
PAGE="00000000-0000-4000-8000-00000000a7c1"
OTHER="00000000-0000-4000-8000-00000000b0b0"
NAME="Archive Door Check"
FILM="$FILMS/$NAME.shotlist"
pass=0
fail=0

# Every run of the app gets the scratch films folder, the scratch relay's
# password, and a deadline. The relay address goes in per run (`--syncsave`).
export SHOTLISTER_FILMS="$FILMS"
export RELAY_TOKEN="$TOKEN"
app() { perl -e 'alarm shift; exec @ARGV' "${DEADLINE:-120}" "$APP" "$@" 2>&1; }
at_relay=(--syncsave "$RELAY" "$TOKEN")

cleanup() {
  [ -n "${HOLDER:-}" ] && kill "$HOLDER" 2>/dev/null
  pkill -f "wrangler.*--port $PORT" 2>/dev/null
  if [ -n "${DEV_PID:-}" ]; then kill "$DEV_PID" 2>/dev/null; wait "$DEV_PID" 2>/dev/null; fi
  sleep 1
  local left; left=$(lsof -ti tcp:"$PORT" 2>/dev/null)
  [ -n "$left" ] && kill -9 $left 2>/dev/null
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

ok() { pass=$((pass + 1)); printf '  ✓  %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  ✗  %s\n' "$1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/       /'; }
check() { if eval "$2"; then ok "$1"; else no "$1" "${3:-}"; fi; }
r2() { (cd "$ROOT/relay" && npx --yes wrangler@4 r2 object "$@" --local --persist-to "$SCRATCH/state" >/dev/null 2>&1); }
id_of() { sed -n 's/.*"project" *: *"\([0-9a-f]*\)".*/\1/p' "$1/remote.json" 2>/dev/null; }

if [ -n "$(lsof -ti tcp:"$PORT" 2>/dev/null)" ]; then
  echo "Something is already listening on port $PORT. Most likely a leftover:"
  echo "    pkill -f 'wrangler.*--port $PORT' && pkill -9 -f workerd"
  exit 1
fi

# ---- a relay of our own ---------------------------------------------------

( cd "$ROOT/relay" && echo "TOKEN=$TOKEN" > .dev.vars && \
  npx --yes wrangler@4 dev --port "$PORT" --persist-to "$SCRATCH/state" --inspector-port 0 \
    --var "COMMIT:checking-commit" --var "DEPLOYED:2026-01-01T00:00:00Z" \
    > "$SCRATCH/dev.log" 2>&1 ) &
DEV_PID=$!
printf 'starting the relay'
for _ in $(seq 1 60); do curl -sf "$BASE/health" >/dev/null 2>&1 && break; printf '.'; sleep 1; done
echo
curl -sf "$BASE/health" >/dev/null 2>&1 || { echo "the relay never came up:"; tail -30 "$SCRATCH/dev.log"; exit 1; }
auth=(-H "Authorization: Bearer $TOKEN")

# ---- a scratch film, linked to a page that is nobody's, on the relay --------

echo "── a scratch film on the scratch relay ──"
out=$(app --newfilm "$NAME" --linkpage "$PAGE" "$NAME")
check "a scratch film is made in the scratch folder and linked by page" \
  '[ -d "$FILM" ] && echo "$out" | grep -q "page \"$PAGE\""' "$out"
app --project "$FILM" --recordfacts '{"director":"Clara Example"}' >/dev/null
out=$(app --project "$FILM" "${at_relay[@]}" --sync)
ID=$(id_of "$FILM")
check "it syncs up to the scratch relay" \
  '[ -n "$ID" ] && curl -s "${auth[@]}" "$BASE/p/$ID/state" | grep -q "\"logs\":\[{"' "$out"
# The portal's own files, as the hub would have written them.
printf '{"version":1,"people":[{"name":"Crew"}],"links":[{"key":"k"}]}' > "$SCRATCH/people.json"
printf '{"version":1,"logline":"words"}' > "$SCRATCH/front.json"
r2 put "shotlister-preview/p/$ID/people.json" --file "$SCRATCH/people.json"
r2 put "shotlister-preview/p/$ID/front.json" --file "$SCRATCH/front.json"

# ---- finding it --------------------------------------------------------------

echo "── found by its page, never by its title ──"
out=$(app "${at_relay[@]}" --archivefilm "$OTHER")
check "a page no film is linked to is refused, and nothing moves" \
  'echo "$out" | grep -q "^archivefilm: refused — no film is linked to this project" && [ -d "$FILM" ]' "$out"
out=$(app "${at_relay[@]}" --archivefilm "$NAME")
check "a title is not a page" \
  'echo "$out" | grep -q "^archivefilm: refused — no film is linked" && [ -d "$FILM" ]' "$out"

# ---- never lose work -----------------------------------------------------------

echo "── never lose work ──"
# A log the relay will not take: its start no longer matches what the relay
# holds (a log may only ever grow), and it is longer, so it wants to go up.
LOG=$(ls "$FILM/changes" | grep '\.log$' | head -1)
cp "$FILM/changes/$LOG" "$SCRATCH/log.keep"
perl -0pi -e 's/Archive Door Check/Archive Door Chock/' "$FILM/changes/$LOG"
printf '999\t0\tff\tS\tff\tnote\tt:more\n' >> "$FILM/changes/$LOG"
out=$(app "${at_relay[@]}" --archivefilm "$PAGE")
check "a change the relay will not take is a refusal that names it" \
  'echo "$out" | grep -q "^archivefilm: refused — not synced: 1 change log, 0 pictures ($LOG" ' "$out"
check "…and nothing moved: the film is in its folder and still on the relay" \
  '[ -d "$FILM" ] && [ ! -d "$FILMS/z-archive/$NAME.shotlist" ] && curl -s "${auth[@]}" "$BASE/p/$ID/state" | grep -q "\"logs\":\[{"'
cp "$SCRATCH/log.keep" "$FILM/changes/$LOG"

# A change made on this Mac and never synced goes up before the film comes off
# — what the console's own fact writes leave in a film nobody has open.
out=$(app --project "$FILM" --recordfacts '{"producer":"Sam Example"}')
check "a change is made on this Mac and not synced" 'echo "$out" | grep -q "^facts: taken producer"' "$out"

# ---- closed first ---------------------------------------------------------------

echo "── closed if it is open, then archived ──"
app --project "$FILM" --holdfilm 60 > "$SCRATCH/holder.log" &
HOLDER=$!
for _ in $(seq 1 40); do grep -q "^holding:" "$SCRATCH/holder.log" 2>/dev/null && break; sleep 0.5; done
DEADLINE=300 out=$(app "${at_relay[@]}" --archivefilm "$PAGE")
wait "$HOLDER" 2>/dev/null; HOLDER=""
check "the window holding the film was asked to let go, and did" \
  'grep -q "^letgo: let go of \"$NAME.shotlist\"" "$SCRATCH/holder.log"' "$(cat "$SCRATCH/holder.log")"
check "the door archives it and says so" \
  'echo "$out" | grep -q "^archivefilm: archived \"$NAME\" at \"$FILMS/z-archive/$NAME.shotlist\""' "$out"
check "the unsynced change went up first" 'echo "$out" | grep -q "sent [1-9][0-9]* logs"' "$out"
check "the film is in the bin, whole, and gone from the films folder" \
  '[ -d "$FILMS/z-archive/$NAME.shotlist/changes" ] && [ ! -d "$FILM" ]'
state=$(curl -s "${auth[@]}" "$BASE/p/$ID/state")
check "the relay holds nothing of it and notes it was archived" \
  'echo "$state" | grep -q "\"logs\":\[\]" && echo "$state" | grep -q "\"gone\":\"archived\""' "$state"
check "the portal's files were set aside first, and the door says where" \
  'echo "$out" | grep -q "portal kept: 2 files at \"kept/$ID/"' "$out"
KEPT=$(echo "$out" | sed -n 's/.*portal kept: [0-9]* files at "\([^"]*\)".*/\1/p')
r2 get "shotlister-preview/${KEPT}people.json" --file "$SCRATCH/kept-people.json"
check "…word for word" 'cmp -s "$SCRATCH/people.json" "$SCRATCH/kept-people.json"'

out=$(app "${at_relay[@]}" --archivefilm "$PAGE")
check "asked again, it is already archived and nothing changes" \
  'echo "$out" | grep -q "^archivefilm: already archived \"$NAME\""' "$out"

# ---- and back -----------------------------------------------------------------

echo "── unarchived ──"
DEADLINE=300 out=$(app "${at_relay[@]}" --unarchivefilm "$PAGE")
check "the door brings it out of the bin" \
  'echo "$out" | grep -q "^unarchivefilm: back \"$NAME\" at \"$FILM\"" && [ -d "$FILM" ] && [ ! -d "$FILMS/z-archive/$NAME.shotlist" ]' "$out"
state=$(curl -s "${auth[@]}" "$BASE/p/$ID/state")
check "and back on the relay, its note gone" \
  'echo "$out" | grep -q "sent [1-9][0-9]* logs" && ! echo "$state" | grep -q "\"gone\"" && echo "$state" | grep -q "\"logs\":\[{"' "$out
$state"
out=$(app "${at_relay[@]}" --unarchivefilm "$PAGE")
check "asked again, it says it is not archived" 'echo "$out" | grep -q "^unarchivefilm: not archived"' "$out"

# ---- two films, one page --------------------------------------------------------

echo "── two films on one page ──"
app --newfilm "$NAME Twin" --linkpage "$PAGE" "$NAME" >/dev/null
out=$(app "${at_relay[@]}" --archivefilm "$PAGE")
check "two films linked to one page are refused — the door does not pick" \
  'echo "$out" | grep -q "^archivefilm: refused — 2 films are linked" && [ -d "$FILM" ] && [ -d "$FILMS/$NAME Twin.shotlist" ]' "$out"

# ---- a film that never went up ------------------------------------------------------

echo "── a film never on the relay ──"
rm -rf "$FILMS/$NAME Twin.shotlist"
app --newfilm "Never Synced" --linkpage "$OTHER" "Never Synced" >/dev/null
out=$(app "${at_relay[@]}" --archivefilm "$OTHER")
check "is archived on this Mac and never signed up to the relay" \
  'echo "$out" | grep -q "^archivefilm: archived \"Never Synced\"" && [ ! -f "$FILMS/z-archive/Never Synced.shotlist/remote.json" ]' "$out"

echo
echo "archive door: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
