#!/bin/bash
# The relay's battery.
#
# Runs the real Worker on this machine — Cloudflare's own runtime, not a
# stand-in — against a throwaway bucket, and asks it everything the apps will
# ask it. Nothing here touches the internet or his account.
#
#   relay/checks.sh
#
# The two rules worth the most attention are the ones that protect against
# damage rather than against a typo: **a log may only ever grow**, and **a
# picture must be what it is called.** Both have their own checks below, in
# both directions.

set -uo pipefail
cd "$(dirname "$0")"

# Homebrew's Node is new enough for wrangler; nvm's older one usually shadows it.
[ -x /opt/homebrew/bin/node ] && export PATH="/opt/homebrew/bin:$PATH"

PORT=${PORT:-8799}
BASE="http://127.0.0.1:$PORT/v1"
TOKEN="checking-token-not-a-secret"
SCRATCH=$(mktemp -d)
PROJECT="00000000000000000000000000000001"
started=$(date +%s)
pass=0
fail=0

# **Kill wrangler itself, not the thing holding the port.** 2026-08-31.
#
# `wrangler dev` runs the actual server in a child process called `workerd`, and
# it *puts a new one back* whenever the old one dies. So killing whatever holds
# the port achieves nothing, and killing only the shell that launched it leaves
# wrangler orphaned onto init, still serving **the version of the script it
# started with**. The next run then talks to a stale server and fails in a way
# that reads exactly like a bug in the code.
cleanup() {
  pkill -f "wrangler.*--port $PORT" 2>/dev/null
  if [ -n "${DEV_PID:-}" ]; then
    kill "$DEV_PID" 2>/dev/null
    wait "$DEV_PID" 2>/dev/null
  fi
  sleep 1
  local left
  left=$(lsof -ti tcp:"$PORT" 2>/dev/null)
  [ -n "$left" ] && kill -9 $left 2>/dev/null
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

if [ -n "$(lsof -ti tcp:"$PORT" 2>/dev/null)" ]; then
  echo "Something is already listening on port $PORT, so this would not be"
  echo "testing the relay in this folder. Most likely a leftover from a run"
  echo "that was interrupted:"
  echo
  echo "    pkill -f 'wrangler.*--port $PORT' && pkill -9 -f workerd"
  exit 1
fi

# ---- the check helpers --------------------------------------------------

# p <what> <expected substring> <curl args...>
p() {
  local what="$1" want="$2"; shift 2
  local got
  got=$(curl -s "$@" 2>&1)
  if [[ "$got" == *"$want"* ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAILED  $what"
    echo "          wanted: $want"
    echo "          got:    ${got:0:300}"
  fi
}

# code <what> <expected status> <curl args...>
code() {
  local what="$1" want="$2"; shift 2
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAILED  $what — wanted $want, got $got"
  fi
}

# same <what> <file a> <file b>
same() {
  if cmp -s "$2" "$3"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAILED  $1 — the bytes came back different"
  fi
}

auth=(-H "Authorization: Bearer $TOKEN")

# ---- start it -----------------------------------------------------------

echo "TOKEN=$TOKEN" > .dev.vars
# `COMMIT` and `DEPLOYED` the way `deploy.sh` passes them — as vars on the
# command, never in a file — so `/v1/version` can be asked below.
npx --yes wrangler@4 dev \
  --port "$PORT" \
  --persist-to "$SCRATCH/state" \
  --inspector-port 0 \
  --var "COMMIT:checking-commit" --var "DEPLOYED:2026-01-01T00:00:00Z" \
  > "$SCRATCH/dev.log" 2>&1 &
DEV_PID=$!

printf 'starting the relay'
for _ in $(seq 1 60); do
  if curl -sf "$BASE/health" > /dev/null 2>&1; then break; fi
  printf '.'
  sleep 1
done
echo
if ! curl -sf "$BASE/health" > /dev/null 2>&1; then
  echo "the relay never came up. Its log:"
  tail -30 "$SCRATCH/dev.log"
  exit 1
fi

# ---- who may ask --------------------------------------------------------

echo "── the door ──"
p "health answers without a token" '"relay":"shotlister"' "$BASE/health"
p "version answers without a token" '"relay":"shotlister"' "$BASE/version"
p "and says the commit it was stamped with" '"commit":"checking-commit"' "$BASE/version"
p "and when" '"deployed":"2026-01-01T00:00:00Z"' "$BASE/version"
# hub/drift.sh reads this route for the live relay; here it reads this run.
drift=$(DRIFT_RELAY_URL="$BASE/version" ../hub/drift.sh relay 2>&1)
if [[ "$drift" == *"checking-commit live"* ]]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "  FAILED  drift.sh reads the live commit"; echo "          got:    $drift"
fi
code "no token is refused" 401 "$BASE/projects"
code "a wrong token is refused" 401 -H "Authorization: Bearer wrong" "$BASE/projects"
code "a token of the right length but wrong is refused" 401 \
  -H "Authorization: Bearer checking-token-not-a-secreT" "$BASE/projects"
code "the right token is let in" 200 "${auth[@]}" "$BASE/projects"

# ---- logs ---------------------------------------------------------------

echo "── change logs ──"
LOG="00000000000000aa-00000000000000bb.log"
printf 'shotlister-log 1\n1\t0\tab\tC\tff\tshot\n' > "$SCRATCH/one.log"

p "an unknown project has nothing in it" '"logs":[]' "${auth[@]}" "$BASE/p/$PROJECT/state"
p "a log can be put" '"size"' "${auth[@]}" -X PUT --data-binary @"$SCRATCH/one.log" \
  "$BASE/p/$PROJECT/log/$LOG"

curl -s "${auth[@]}" "$BASE/p/$PROJECT/log/$LOG" > "$SCRATCH/back.log"
same "and comes back byte for byte" "$SCRATCH/one.log" "$SCRATCH/back.log"

p "and is listed with its size" "\"name\":\"$LOG\",\"size\":$(wc -c < "$SCRATCH/one.log" | tr -d ' ')" \
  "${auth[@]}" "$BASE/p/$PROJECT/state"

echo "── a log may only ever grow ──"
cat "$SCRATCH/one.log" > "$SCRATCH/two.log"
printf '2\t0\tab\tS\tff\tlens\t50mm\n' >> "$SCRATCH/two.log"
code "adding to the end is fine" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/two.log" \
  "$BASE/p/$PROJECT/log/$LOG"

printf 'shotlister-log 1\n' > "$SCRATCH/short.log"
code "a truncated log is refused" 409 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/short.log" \
  "$BASE/p/$PROJECT/log/$LOG"
p "and says why" "rewrite" "${auth[@]}" -X PUT --data-binary @"$SCRATCH/short.log" \
  "$BASE/p/$PROJECT/log/$LOG"

printf 'shotlister-log 1\n9\t0\tzz\tC\tee\tshot\n' > "$SCRATCH/other.log"
code "a log that disagrees about its own past is refused" 409 "${auth[@]}" -X PUT \
  --data-binary @"$SCRATCH/other.log" "$BASE/p/$PROJECT/log/$LOG"

code "unless the fold says so" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/other.log" \
  "$BASE/p/$PROJECT/log/$LOG?rewrite=1"

echo "── names ──"
code "a made-up log name is refused" 400 "${auth[@]}" -X PUT --data-binary 'x' \
  "$BASE/p/$PROJECT/log/notes.txt"
code "and so is a walk up the tree" 400 "${auth[@]}" \
  "$BASE/p/$PROJECT/log/..%2F..%2Fmanifest.json"
code "a project name that is not one is refused" 400 "${auth[@]}" "$BASE/p/..%2F..%2Fetc/state"

MARK="00000000000000aa-00000000000000cc.device"
code "an identity mark is empty and still allowed" 200 "${auth[@]}" -X PUT --data-binary '' \
  "$BASE/p/$PROJECT/log/$MARK"
p "and is listed beside the logs" "$MARK" "${auth[@]}" "$BASE/p/$PROJECT/state"

# ---- media --------------------------------------------------------------

echo "── pictures and clips ──"
printf 'pretend this is a photograph' > "$SCRATCH/pic.bin"
FULL=$(shasum -a 256 "$SCRATCH/pic.bin" | cut -d' ' -f1)
STEM=$(echo "$FULL" | cut -c1-32)
PIC="$STEM.jpg"
ABSENT="ffffffffffffffffffffffffffffffff.jpg"

p "a picture goes up under its stored name" '"stored":true' "${auth[@]}" -X PUT \
  --data-binary @"$SCRATCH/pic.bin" -H "x-sha256: $FULL" "$BASE/p/$PROJECT/media/$PIC"
curl -s "${auth[@]}" "$BASE/p/$PROJECT/media/$PIC" > "$SCRATCH/pic.back"
same "and comes back byte for byte" "$SCRATCH/pic.bin" "$SCRATCH/pic.back"

p "a jpeg is served as one, so a browser will draw it" 'image/jpeg' \
  -D - -o /dev/null "${auth[@]}" "$BASE/p/$PROJECT/media/$PIC"

p "the same picture twice is not stored twice" '"stored":false' "${auth[@]}" -X PUT \
  --data-binary @"$SCRATCH/pic.bin" "$BASE/p/$PROJECT/media/$PIC"

code "bytes that do not match a claimed hash are refused" 400 "${auth[@]}" -X PUT \
  --data-binary @"$SCRATCH/pic.bin" \
  -H "x-sha256: 0000000000000000000000000000000000000000000000000000000000000000" \
  "$BASE/p/$PROJECT/media/$ABSENT"
code "and nothing was stored under that name" 404 "${auth[@]}" "$BASE/p/$PROJECT/media/$ABSENT"

# **The still that stands for a clip shares the clip's name and not its bytes.**
# A relay that insisted on the hash would refuse the poster of every video in
# the project. Found by hashing his real media rather than by assuming.
printf 'fake mp4 bytes' > "$SCRATCH/clip.mp4"
CLIPSTEM=$(shasum -a 256 "$SCRATCH/clip.mp4" | cut -c1-32)
printf 'the poster frame, which hashes to something else entirely' > "$SCRATCH/clip.png"
p "a clip goes up" '"stored":true' "${auth[@]}" -X PUT --data-binary @"$SCRATCH/clip.mp4" \
  "$BASE/p/$PROJECT/media/$CLIPSTEM.mp4"
p "and its poster, under the same name and a different extension" '"stored":true' \
  "${auth[@]}" -X PUT --data-binary @"$SCRATCH/clip.png" "$BASE/p/$PROJECT/media/$CLIPSTEM.png"
p "a clip is served as video, so it will play" 'video/mp4' \
  -D - -o /dev/null "${auth[@]}" "$BASE/p/$PROJECT/media/$CLIPSTEM.mp4"
# A whole file is a whole answer. R2 reports a range for an ordinary get too,
# so believing it turned every picture into a 206.
code "asking for the whole thing gets 200, not 206" 200 "${auth[@]}" \
  "$BASE/p/$PROJECT/media/$CLIPSTEM.mp4"
p "and can be seeked into rather than swallowed whole" '206' \
  -o /dev/null -w '%{http_code}' -H 'Range: bytes=2-5' "${auth[@]}" \
  "$BASE/p/$PROJECT/media/$CLIPSTEM.mp4"

p "it says which pictures it has not got" "\"missing\":[\"$ABSENT\"]" "${auth[@]}" \
  -X POST -H 'content-type: application/json' \
  -d "{\"names\":[\"$PIC\",\"$ABSENT\"]}" "$BASE/p/$PROJECT/media/missing"
p "and can list what it does have" "$PIC" "${auth[@]}" "$BASE/p/$PROJECT/media"
code "a made-up media name is refused" 400 "${auth[@]}" "$BASE/p/$PROJECT/media/secrets.env"

# Without this the relay was the one place a deleted photograph lived for ever.
code "a picture can be taken off again" 200 "${auth[@]}" -X DELETE \
  "$BASE/p/$PROJECT/media/$CLIPSTEM.png"
code "and is then gone" 404 "${auth[@]}" "$BASE/p/$PROJECT/media/$CLIPSTEM.png"
code "the one beside it is untouched" 200 "${auth[@]}" "$BASE/p/$PROJECT/media/$CLIPSTEM.mp4"

# ---- the picture door ---------------------------------------------------

# **The one route with no password**, so Google's servers can fetch a frame for
# an `IMAGE()` cell in the exported spreadsheet. Everything here is about how
# narrow it is: pictures only, one exact name only, and reading only.

echo "── the picture door ──"
PUBLIC="http://127.0.0.1:$PORT/i"

curl -s "$PUBLIC/$PROJECT/$PIC" > "$SCRATCH/pic.public"
same "a picture comes back with no token at all" "$SCRATCH/pic.bin" "$SCRATCH/pic.public"
p "and still says what it is, so Sheets will draw it" 'image/jpeg' \
  -D - -o /dev/null "$PUBLIC/$PROJECT/$PIC"

code "a clip is not fetchable this way" 404 "$PUBLIC/$PROJECT/$CLIPSTEM.mp4"
code "nor is anything that is not a picture's name" 404 "$PUBLIC/$PROJECT/secrets.env"
code "a made-up project is refused" 400 "$PUBLIC/not-a-project/$PIC"
code "nothing can be listed through it" 404 "$PUBLIC/$PROJECT"
code "and it will not write" 405 -X PUT --data-binary @"$SCRATCH/pic.bin" \
  "$PUBLIC/$PROJECT/$PIC"
code "and it will not delete" 405 -X DELETE "$PUBLIC/$PROJECT/$PIC"
code "the picture is still there afterwards" 200 "${auth[@]}" \
  "$BASE/p/$PROJECT/media/$PIC"

# ---- the manifest and the list -----------------------------------------

echo "── the rest ──"
printf '{"format":1,"title":"Checking"}' > "$SCRATCH/manifest.json"
code "the manifest can be put" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/manifest.json" \
  "$BASE/p/$PROJECT/manifest"
p "and read back" '"title":"Checking"' "${auth[@]}" "$BASE/p/$PROJECT/manifest"
p "the project is in the list" "\"project\":\"$PROJECT\"" "${auth[@]}" "$BASE/projects"

code "a project can be taken off entirely" 200 "${auth[@]}" -X DELETE "$BASE/p/$PROJECT/manifest"
code "and its manifest is then gone" 404 "${auth[@]}" "$BASE/p/$PROJECT/manifest"
code "a log can be deleted, for folding" 200 "${auth[@]}" -X DELETE "$BASE/p/$PROJECT/log/$LOG"
code "and is then gone" 404 "${auth[@]}" "$BASE/p/$PROJECT/log/$LOG"

# ---- taking a whole film off -------------------------------------------
#
# **What archiving and deleting both stand on.** Deleting a film by its pieces
# leaves behind anything nobody here owns the name of, and 268 bytes is enough
# to keep it in the list and draw it on his Projects screen. So this checks the
# only thing that matters: after it, the film is not in the list.
echo "── a whole film ──"
WHOLE="00000000000000000000000000000002"
printf '{"format":1,"title":"Whole"}' > "$SCRATCH/whole.json"
code "a second film is put up" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/whole.json" \
  "$BASE/p/$WHOLE/manifest"
code "with a log" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/one.log" \
  "$BASE/p/$WHOLE/log/$LOG"
p "and it is in the list" "\"project\":\"$WHOLE\"" "${auth[@]}" "$BASE/projects"
p "the whole film can be taken off in one" '"gone":2' "${auth[@]}" -X DELETE "$BASE/p/$WHOLE"
# A film with no portal files has nothing to set aside (2026-10-04).
p "and with nothing of the portal's in it, nothing is set aside" '"kept":null' "${auth[@]}" -X DELETE "$BASE/p/$WHOLE"
code "its manifest is gone" 404 "${auth[@]}" "$BASE/p/$WHOLE/manifest"
code "its log is gone" 404 "${auth[@]}" "$BASE/p/$WHOLE/log/$LOG"
if curl -s "${auth[@]}" "$BASE/projects" | grep -q "$WHOLE"; then
  fail=$((fail + 1)); echo "  FAILED  the film is still in the list after being taken off"
else
  pass=$((pass + 1))
fi
code "taking off a film that is not there is not an error" 200 "${auth[@]}" -X DELETE "$BASE/p/$WHOLE"
code "and the address refuses anything but a delete" 405 "${auth[@]}" "$BASE/p/$WHOLE"

# ---- leftovers of a deleted project are not a film — 2026-10-17 -------------
# A project deleted from the console can have portal files written back under
# its old id (front page, covers): no manifest, no logs, and no portal mark.
# Listed, it drew a nameless project on every Mac and iPhone.
echo "── leftovers with no film ──"
LEFT="00000000000000000000000000000007"
printf '{"version":1,"logline":"words"}' > "$SCRATCH/left-front.json"
(npx --yes wrangler@4 r2 object put "shotlister-preview/p/$LEFT/front.json" --file "$SCRATCH/left-front.json" \
  --local --persist-to "$SCRATCH/state" >/dev/null 2>&1)
if curl -s "${auth[@]}" "$BASE/projects" | grep -q "$LEFT"; then
  fail=$((fail + 1)); echo "  FAILED  leftover portal files with no manifest or logs are in the film listing"
else
  pass=$((pass + 1))
fi

# ---- a portal with no film is not a film — 2026-09-16 ----------------------
# The hub marks a project's own prefix with `portal.json` when the console
# makes it a web portal with no Shotlister film behind it. Listed here it
# would reach every Mac and iPhone as an empty film named by its id. It is
# left out — and the whole-prefix delete still takes it off, because that is
# the door the console uses to take a portal down.
echo "── a portal with no film ──"
PORTAL="00000000000000000000000000000004"
printf '{"version":1,"title":"Just a Portal","page":"%s"}' "$PORTAL" > "$SCRATCH/portal.json"
printf '{"version":1,"logline":"words"}' > "$SCRATCH/front.json"
(npx --yes wrangler@4 r2 object put "shotlister-preview/p/$PORTAL/portal.json" --file "$SCRATCH/portal.json" \
  --local --persist-to "$SCRATCH/state" >/dev/null 2>&1)
(npx --yes wrangler@4 r2 object put "shotlister-preview/p/$PORTAL/front.json" --file "$SCRATCH/front.json" \
  --local --persist-to "$SCRATCH/state" >/dev/null 2>&1)
if curl -s "${auth[@]}" "$BASE/projects" | grep -q "$PORTAL"; then
  fail=$((fail + 1)); echo "  FAILED  a portal with no film is in the film listing"
else
  pass=$((pass + 1))
fi
# **A log does not make it a film** (SL-1376). On 2026-10-01 a chat wrote two
# into Halcyon, a portal with no film, and this listing — which kept a portal
# once it had any log — offered it to every Mac and iPhone as a film with no
# manifest. The one rule (`relay/portal.js`): a mark and no manifest.
code "a stray log lands under the portal" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/one.log" \
  "$BASE/p/$PORTAL/log/$LOG"
if curl -s "${auth[@]}" "$BASE/projects" | grep -q "$PORTAL"; then
  fail=$((fail + 1)); echo "  FAILED  a portal with a stray log is in the film listing"
else
  pass=$((pass + 1))
fi
# **But never without setting the portal aside first** (2026-10-04, his ask:
# "without wiping any data — I have teams relying on my current portal"). The
# portal's own files are copied to `kept/<project>/<stamp>/` before the delete;
# the stray log is the film's and is not. Nothing that lists `p/` sees `kept/`.
GONE_SAID=$(curl -s "${auth[@]}" -X DELETE "$BASE/p/$PORTAL")
if echo "$GONE_SAID" | grep -q '"gone":3'; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "  FAILED  the whole prefix can still be taken off in one"; echo "          got: $GONE_SAID"; fi
if echo "$GONE_SAID" | grep -q "\"kept\":{\"at\":\"kept/$PORTAL/" && echo "$GONE_SAID" | grep -q '"files":2'; then
  pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAILED  the portal's two files were set aside first"; echo "          got: $GONE_SAID"; fi
KEPT_AT=$(echo "$GONE_SAID" | sed -n 's/.*"at":"\([^"]*\)".*/\1/p')
(npx --yes wrangler@4 r2 object get "shotlister-preview/${KEPT_AT}front.json" --file "$SCRATCH/kept-front.json" \
  --local --persist-to "$SCRATCH/state" >/dev/null 2>&1)
if grep -q '"logline":"words"' "$SCRATCH/kept-front.json" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "  FAILED  the set-aside front.json is the portal's own, word for word"; fi
(npx --yes wrangler@4 r2 object get "shotlister-preview/${KEPT_AT}logs/$LOG" --file "$SCRATCH/kept-log" \
  --local --persist-to "$SCRATCH/state" >/dev/null 2>&1)
if [ -s "$SCRATCH/kept-log" ]; then fail=$((fail + 1)); echo "  FAILED  the film's own log was set aside too"; else pass=$((pass + 1)); fi
if curl -s "${auth[@]}" "$BASE/projects" | grep -q "kept"; then
  fail=$((fail + 1)); echo "  FAILED  something set aside reached the film listing"
else
  pass=$((pass + 1))
fi

# ---- and why it went, remembered — his ruling 2026-09-16 --------------------
# One Projects list on every device: a film archived on the Mac is archived on
# the phone at its next sync, never asked about. So a delete may carry a fate,
# the state and the listing repeat it, and a log put under the name again
# clears it — that is what putting a film back is.
echo "── a film's fate ──"
code "the film is put up again" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/one.log" \
  "$BASE/p/$WHOLE/log/$LOG"
p "and taken off as archived" '"fate":"archived"' "${auth[@]}" -X DELETE "$BASE/p/$WHOLE?fate=archived"
p "its state says so" '"gone":"archived"' "${auth[@]}" "$BASE/p/$WHOLE/state"
p "and so does the listing" "\"project\":\"$WHOLE\",\"logs\":0,\"media\":0,\"bytes\":0,\"gone\":\"archived\"" "${auth[@]}" "$BASE/projects"
code "a log put under the name is the film coming back" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/one.log" \
  "$BASE/p/$WHOLE/log/$LOG"
if curl -s "${auth[@]}" "$BASE/p/$WHOLE/state" | grep -q '"gone"'; then
  fail=$((fail + 1)); echo "  FAILED  the fate outlived the film's return"
else
  pass=$((pass + 1))
fi
p "taken off again" '"fate":"archived"' "${auth[@]}" -X DELETE "$BASE/p/$WHOLE?fate=archived"
p "and the back door clears the note before anything is sent" '"back":true' "${auth[@]}" -X PUT "$BASE/p/$WHOLE/back"
if curl -s "${auth[@]}" "$BASE/p/$WHOLE/state" | grep -q '"gone"'; then
  fail=$((fail + 1)); echo "  FAILED  the back door left the note"
else
  pass=$((pass + 1))
fi
p "deleted is remembered the same way" '"fate":"deleted"' "${auth[@]}" -X DELETE "$BASE/p/$WHOLE?fate=deleted"
p "and said" '"gone":"deleted"' "${auth[@]}" "$BASE/p/$WHOLE/state"
p "a bare delete leaves no note" '"fate":null' "${auth[@]}" -X DELETE "$BASE/p/$WHOLE"
if curl -s "${auth[@]}" "$BASE/p/$WHOLE/state" | grep -q '"gone"'; then
  fail=$((fail + 1)); echo "  FAILED  a bare delete should clear the note"
else
  pass=$((pass + 1))
fi

# ---- the open line ------------------------------------------------------
#
# **The handshake only.** Whether the word actually reaches the other device is
# proved app-to-app, by two copies of the Mac app against a real relay — the
# same way the sync itself is proved.
#
# It is not checked here with Node because Node's built-in `WebSocket` cannot
# set an `Authorization` header (nor can a browser's — it is WHATWG's rule, not
# Node's), and the relay refuses anything unsigned. Swift's
# `URLSessionWebSocketTask` takes a whole `URLRequest`, so the apps are fine.
# **If a browser ever needs to watch (Ref 403), that is the thing that has to
# change**, and it means a token in the query string.

echo "── the open line ──"
# **`--max-time`, or a success hangs the battery.** A handshake that works leaves
# the line *open*, which is the whole point of it — and curl then waits on it for
# ever. The first version of this check passed and never returned.
upgrade=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==" \
  "$BASE/p/$PROJECT/watch")
if [ "$upgrade" = "101" ]; then
  echo "  ✓ a device can open a line to a film"; pass=$((pass + 1))
else
  echo "  ✗ opening a line answered $upgrade, not 101"; fail=$((fail + 1))
fi

code "and asking for it without a websocket is refused" 426 "${auth[@]}" --max-time 5 \
  "$BASE/p/$PROJECT/watch"
code "and without the password" 401 --max-time 5 "$BASE/p/$PROJECT/watch"

# ---- a token per device -------------------------------------------------
#
# The master password mints a token for one device, that token gets in and is
# named on what it writes, and taking it away touches nothing else.

echo "── a token per device ──"
minted=$(curl -s "${auth[@]}" -X POST -H 'content-type: application/json' \
  -d '{"name":"  Nathaniel'"'"'s   iPhone "}' "$BASE/devices")
DEVICE_TOKEN=$(echo "$minted" | sed -nE 's/.*"token":"([0-9a-f]{64})".*/\1/p')
DEVICE_ID=$(echo "$minted" | sed -nE 's/.*"id":"([0-9a-f]{64})".*/\1/p')
if [ -n "$DEVICE_TOKEN" ] && [ -n "$DEVICE_ID" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "  FAILED  the master password mints a device token"; echo "          got:    ${minted:0:300}"
fi
p "and the name is tidied" '"name":"Nathaniel'"'"'s iPhone"' "${auth[@]}" "$BASE/devices"
code "a device without a name is refused" 400 "${auth[@]}" -X POST -H 'content-type: application/json' -d '{}' "$BASE/devices"
code "minting needs the master password" 401 -X POST -H 'content-type: application/json' -d '{"name":"x"}' "$BASE/devices"
device=(-H "Authorization: Bearer $DEVICE_TOKEN")
code "the device's token is let in" 200 "${device[@]}" "$BASE/projects"
code "a device may not mint devices" 403 "${device[@]}" -X POST -H 'content-type: application/json' -d '{"name":"x"}' "$BASE/devices"
code "a device may not list devices" 403 "${device[@]}" "$BASE/devices"
code "a made-up token of the right shape is refused" 401 \
  -H "Authorization: Bearer 0000000000000000000000000000000000000000000000000000000000000000" "$BASE/projects"
p "the list names the device and never its token" '"name":"Nathaniel'"'"'s iPhone"' "${auth[@]}" "$BASE/devices"
listed=$(curl -s "${auth[@]}" "$BASE/devices")
if [[ "$listed" != *"$DEVICE_TOKEN"* ]]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "  FAILED  the token is not kept anywhere it can be read back"; fi

DLOG="00000000000000cc-00000000000000dd.log"
printf 'shotlister-log 1\n1\t0\tab\tC\tff\tshot\n' > "$SCRATCH/device.log"
code "a device can put a log" 200 "${device[@]}" -X PUT --data-binary @"$SCRATCH/device.log" \
  "$BASE/p/$PROJECT/log/$DLOG"
p "and the listing says which device wrote it" "\"name\":\"$DLOG\",\"size\":$(wc -c < "$SCRATCH/device.log" | tr -d ' '),\"by\":\"Nathaniel's iPhone\"" \
  "${auth[@]}" "$BASE/p/$PROJECT/state"
mlog=$(curl -s "${auth[@]}" "$BASE/p/$PROJECT/state" | tr ',' '\n' | grep -A1 "\"$LOG\"" | tr -d '\n')
if [[ "$mlog" != *'"by"'* ]]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "  FAILED  a log the master password wrote names nobody"; echo "          got:    $mlog"; fi

code "revoking a device that is not there is 404" 404 "${auth[@]}" -X DELETE \
  "$BASE/devices/1111111111111111111111111111111111111111111111111111111111111111"
code "a device may not revoke" 403 "${device[@]}" -X DELETE "$BASE/devices/$DEVICE_ID"
p "the master password revokes a device" '"revoked":true' "${auth[@]}" -X DELETE "$BASE/devices/$DEVICE_ID"
code "and its token stops working" 401 "${device[@]}" "$BASE/projects"
code "and its log is still there" 200 "${auth[@]}" "$BASE/p/$PROJECT/log/$DLOG"

# ---- a fold, carried to the relay ---------------------------------------
#
# Ref 192's other half: a device's `<device>.folded` record retires that
# device's own logs here, once every log it rewrote has arrived.

echo "── a fold ──"
FDEV="00000000000000ee"
FOLDED="$FDEV-0000000000000001.log"     # retired by the fold
KEPT="$FDEV-0000000000000002.log"       # what the fold rewrote — holds everything
printf 'shotlister-log 1\n1\t0\tab\tC\tff\tshot\n' > "$SCRATCH/folded.log"
printf 'shotlister-log 1\n1\t0\tab\tC\tff\tshot\n2\t0\tab\tS\tff\tlens\t50mm\n' > "$SCRATCH/kept.log"
printf 'shotlister-folded 1\nR\t%s\nW\t%s\n' "$FOLDED" "$KEPT" > "$SCRATCH/fold.folded"
code "the retired log is put" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/folded.log" "$BASE/p/$PROJECT/log/$FOLDED"
p "a record sent before the rewritten log waits" '"waiting":1' "${auth[@]}" -X PUT --data-binary @"$SCRATCH/fold.folded" \
  "$BASE/p/$PROJECT/log/$FDEV.folded"
code "and the retired log is still here" 200 "${auth[@]}" "$BASE/p/$PROJECT/log/$FOLDED"
code "the rewritten log arrives" 200 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/kept.log" "$BASE/p/$PROJECT/log/$KEPT"
p "the record sent again retires it" '"retired":1' "${auth[@]}" -X PUT --data-binary @"$SCRATCH/fold.folded" \
  "$BASE/p/$PROJECT/log/$FDEV.folded"
code "and the retired log is gone" 404 "${auth[@]}" "$BASE/p/$PROJECT/log/$FOLDED"
code "and the rewritten one stays" 200 "${auth[@]}" "$BASE/p/$PROJECT/log/$KEPT"
p "the record can be read back" "R	$FOLDED" "${auth[@]}" "$BASE/p/$PROJECT/log/$FDEV.folded"
# `$DLOG` is another device's, put by the device-token checks above; `$LOG`
# went with the whole film earlier.
printf 'shotlister-folded 1\nR\t%s\nW\t%s\n' "$DLOG" "$KEPT" > "$SCRATCH/theft.folded"
code "a fold may not retire another device's log" 400 "${auth[@]}" -X PUT --data-binary @"$SCRATCH/theft.folded" \
  "$BASE/p/$PROJECT/log/$FDEV.folded"
code "and that log is untouched" 200 "${auth[@]}" "$BASE/p/$PROJECT/log/$DLOG"
code "a record needs the password" 401 -X PUT --data-binary @"$SCRATCH/fold.folded" "$BASE/p/$PROJECT/log/$FDEV.folded"

# ---- the layout, named once ---------------------------------------------
#
# `layout.json` is the bucket's one source. The two workers import it; three
# readers cannot (a page, a Rust crate, two Swift apps) and repeat a word each,
# so this measures them against it. A miss here is the poster fault of
# 2026-09-15 about to happen again, caught before a deploy.

echo "── the layout ──"
ROOT="$(cd .. && pwd)"
layout() { python3 -c "import json,sys; d=json.load(open('layout.json'))
for k in sys.argv[1].split('.'): d=d[k]
print(d)" "$1"; }

# said <what> <expected> <got>
said() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "  FAILED  $1"; echo "          layout.json: $2"; echo "          found:       $3"; fi
}

# The engine's names are the ones the relay refuses everything else against.
said "the manifest is what the engine calls it" "$(layout engine.manifest)" \
  "$(sed -nE 's/^pub const MANIFEST: &str = "([^"]*)";/\1/p' "$ROOT/engine/src/package.rs")"
said "a log's extension is the engine's" "$(layout engine.logExtension)" \
  "$(sed -nE 's/^pub const LOG_EXTENSION: &str = "([^"]*)";/\1/p' "$ROOT/engine/src/package.rs")"
said "a device mark's extension is the engine's" "$(layout engine.markExtension)" \
  "$(sed -nE 's/^pub const DEVICE_MARK_EXTENSION: &str = "([^"]*)";/\1/p' "$ROOT/engine/src/package.rs")"
said "a fold record's extension is the engine's" "$(layout engine.foldExtension)" \
  "$(sed -nE 's/^pub const FOLD_RECORD_EXTENSION: &str = "([^"]*)";/\1/p' "$ROOT/engine/src/package.rs")"
said "and the manifest key ends in it" "$(layout engine.manifest)" "$(layout manifest)"
ends() { [[ "$1" == *"\\.$2\$" ]] && echo yes || echo no; }
said "the log pattern ends in the engine's extension" "yes" \
  "$(ends "$(layout names.log)" "$(layout engine.logExtension)")"
said "the mark pattern ends in the engine's extension" "yes" \
  "$(ends "$(layout names.mark)" "$(layout engine.markExtension)")"
said "the fold pattern ends in the engine's extension" "yes" \
  "$(ends "$(layout names.fold)" "$(layout engine.foldExtension)")"

# The readers that cannot import it, each repeating one word.
said "the page asks for the poster the layout names" "$(layout poster.extension)" \
  "$(sed -nE 's/^const POSTER = "([^"]*)";/\1/p' "$ROOT/hub/public/film.js")"
said "the browser engine asks for the same poster" "$(layout poster.extension)" \
  "$(sed -nE 's/^const POSTER: &str = "([^"]*)";/\1/p' "$ROOT/web/src/lib.rs")"
# One carrier for both apps since 2026-09-16 (`shared/RelayCarrier.swift`),
# so one place to measure, not two.
said "both apps put and fetch under the media folder the layout names" "$(layout media)" \
  "$(grep -oE 'to: "\\\(root\)/media/' "$ROOT/shared/RelayCarrier.swift" | head -1 | sed -E 's/.*\)\///')"
said "and read the manifest by the engine's name" "$(layout engine.manifest)" \
  "$(sed -nE 's/^    static let manifestFile = "([^"]*)"/\1/p' "$ROOT/shared/RelayCarrier.swift")"

# And nobody has started spelling a path by hand again.
spelled=$(grep -n 'p/\${' src/worker.js "$ROOT"/hub/src/*.js | grep -v '`mcp/\|`hub/mcp/' || true)
if [ -z "$spelled" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "  FAILED  a bucket path is spelled by hand instead of taken from layout.js"; echo "$spelled" | sed 's/^/          /'; fi

# ---- how it ended -------------------------------------------------------

echo "────"
echo "passed $pass, failed $fail, $(( $(date +%s) - started ))s"
[ "$fail" -eq 0 ]
