#!/bin/bash
# The hub, checked against Cloudflare's own runtime.
#
# Same shape as `relay/checks.sh`: start the worker locally, put a small film in
# the bucket, then ask it things as several different people. **Local only** —
# it never touches the real bucket, and the identity it uses cannot work
# anywhere but localhost (see `identify` in src/worker.js).
#
# The bucket seeded is the *preview* one, which is what a local run binds.
#
# What is actually being checked here is not "does a page come back". It is the
# one rule the hub exists to hold: **a viewer is refused by the server, not by
# the page.**
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PORT="${PORT:-8788}"
STATE="$(mktemp -d)"
FILM="01a02852ebb00198e46a252100000000"
OWNER="owner@example.com"
DIRECTOR="clara@example.com"
STRANGER="nobody@example.com"
WORK="owner@your-domain.example"

# **Wrangler from `node_modules`, not `npx`.** npx re-resolves the package on
# every call: 35 seconds a put against 0.8. Seeding a real film went from over
# an hour to under three minutes when this changed.
W="$HERE/node_modules/.bin/wrangler"
[ -x "$W" ] || W="npx --yes wrangler@4"

pass=0; fail=0
say() { printf "  %-58s %s\n" "$1" "$2"; }
ok()  { pass=$((pass+1)); say "$1" "PASS"; }
no()  { fail=$((fail+1)); say "$1" "FAIL — $2"; }

# **Kill by port, not by the pid we started.** `( … ) &` gives back the pid of
# the subshell, not of the node process inside it, so killing it leaves the
# worker running — and a stale worker holding this port answers the next run's
# questions out of a bucket that has since been deleted. That is exactly how
# three checks "broke" after a change that could not have broken them.
freeport() {
  local held
  held=$(lsof -ti "tcp:$PORT" 2>/dev/null)
  [ -n "$held" ] && kill -9 $held 2>/dev/null
  for _ in $(seq 1 20); do
    lsof -ti "tcp:$PORT" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

cleanup() {
  freeport
  # **And the wrangler that owned the port.** `freeport` kills whatever holds
  # the port — that is workerd, the child — and the `wrangler dev` parent
  # lived on, one per run, until the machine was carrying sixty-six of them
  # (Ref 930, four times). Name it by its own port so nobody else's dies.
  # TERM first, so wrangler takes its workerd with it; -9 straight away
  # leaves that child orphaned on an ephemeral port nothing can find.
  pkill -TERM -f "wrangler.*dev --local --port $PORT" 2>/dev/null
  sleep 1
  pkill -9 -f "wrangler.*dev --local --port $PORT" 2>/dev/null
  rm -rf "$STATE"
}
trap cleanup EXIT

# **A failed build must stop the run.** It did not, and the cost was real: the
# engine's picture type changed under this crate, `build.sh` failed, and every
# check afterwards passed — against a stale `.wasm` left over from the last
# build. Twenty-nine green ticks measuring a program that no longer compiled.
# **A fresh worktree has no `.dev.vars`** — it is gitignored — and without
# `HUB_DEV_EMAIL` every `?as=` identity is refused, so the run dies at "cannot
# see the film that was just seeded", which reads as a bucket fault. Say the
# real thing. It holds only the local checking identity; copy it across.
[ -f "$HERE/.dev.vars" ] || {
  echo "no hub/.dev.vars here — copy hub/.dev.vars.example to hub/.dev.vars (it names the local checking identity, nothing secret)"
  exit 1; }

echo "Building the browser half…"
"$HERE/build.sh" >/dev/null || { echo "the browser half would not build — nothing below would mean anything"; exit 1; }

echo "Putting a small film in a local bucket…"
SEED="$(mktemp -d)"
# **A mark on the manifest and none on any card**, the way a film looks when
# its colour was picked on the Mac and no refresh has run: every page under it
# must still wear it (`ownMark` in src/front.js).
printf '{"format":1,"project":"%s","title":"Call Her Back","engine":"0.1.0","markPath":"M10 4A6 6 0 1 0 10 16A6 6 0 1 0 10 4Z","markColour":"#5E9B3C"}' "$FILM" > "$SEED/manifest.json"
printf 'shotlister-log 1\n' > "$SEED/0000000000000001-000000000000000a.log"

put() { # put <key> <file>
  (cd "$HERE" && $W r2 object put "shotlister-preview/$1" --file "$2" --local --persist-to "$STATE" >/dev/null 2>&1)
}
put "p/$FILM/manifest.json" "$SEED/manifest.json"
put "p/$FILM/logs/0000000000000001-000000000000000a.log" "$SEED/0000000000000001-000000000000000a.log"
rm -rf "$SEED"

echo "Starting the hub…"
freeport
# **Access blanked for the run, explicitly.** The checking identity is refused
# once Access is configured, so a checking run against the real wrangler.toml
# cannot sign in to anything. Said here rather than left to `.dev.vars`, which
# is not committed and so cannot be relied on to exist.
# **And the console's token, a known one.** `CONSOLE_TOKEN` is a secret in the
# air; here it is the same made-up word the relay's battery uses, so the door
# can be knocked on and refused in the same run.
# **And a Notion of its own, on this machine** (Ref 1155): `notionfake.mjs`
# answers the calls the portal's Refresh from Notion makes, so the battery
# checks that road without ever reading his workspace. The worker only
# honours `NOTION_API` when it points at localhost.
NPORT=$((PORT + 7))
lsof -ti "tcp:$NPORT" 2>/dev/null | xargs kill -9 2>/dev/null
node "$HERE/notionfake.mjs" "$NPORT" >/dev/null 2>&1 &
FAKE=$!
trap 'kill $FAKE 2>/dev/null; wait $FAKE 2>/dev/null; cleanup' EXIT
(cd "$HERE" && $W dev --local --port "$PORT" --persist-to "$STATE" \
  --var ACCESS_TEAM:"" --var ACCESS_AUD:"" --var CONSOLE_TOKEN:"checking-token-not-a-secret" \
  --var NOTION_TOKEN:"checking-notion-token" --var NOTION_API:"http://127.0.0.1:$NPORT/v1/" \
  --var COMMIT:"checking-commit" --var DEPLOYED:"2026-01-01T00:00:00Z" >/dev/null 2>&1) &
# **`--max-time`, or a sick worker hangs the run forever.** Without it this poll
# is `curl` with no deadline: a worker that accepts the connection and never
# answers — which is what a machine carrying thirty-six leaked `wrangler dev`
# processes produces, and also what a worker whose bundle failed to build
# produces — turns a 40-second wait into an unbounded one. The run then neither
# passes nor fails; it sits at "Starting the hub…" indefinitely. That cost an
# hour on 2026-09-05, twice, and both times it read as the machine being slow.
for _ in $(seq 1 40); do
  curl -fsS -m 4 "http://localhost:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS -m 4 "http://localhost:$PORT/health" >/dev/null 2>&1 || {
  echo "the hub would not start — check the bundle builds: hub/node_modules/.bin/wrangler deploy --dry-run"
  exit 1; }

# **Prove it is ours before asking it anything.** A worker answering on this
# port that cannot see the film we just seeded is somebody else's, and every
# check after this would be measuring the wrong program.
if ! curl -fsS "http://localhost:$PORT/f/$FILM/api/manifest?as=$OWNER" 2>/dev/null | grep -q "Call Her Back"; then
  echo "the hub on port $PORT cannot see the film that was just seeded — something else is holding it"
  exit 1
fi
echo

# code <url> [curl args…] — the status a request comes back with
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
body() { curl -s "$@"; }
header() { curl -s -o /dev/null -w "%header{$2}" "$1"; }   # header <url> <name>
H="http://localhost:$PORT"

# ---- who you are ------------------------------------------------------------
[ "$(code "$H/health")" = 200 ] && ok "health answers without knowing anybody" || no "health answers without knowing anybody" "not 200"

# ---- the film's own mark ----------------------------------------------------
# **Every page wears the film — his ruling, 2026-09-16.** This film has no
# card yet; its mark is on its manifest alone, the way a film looks when its
# colour was picked on the Mac and no refresh has run. It must still reach
# the page (`ownMark` in src/front.js). A card that carries Notion's mark wins
# once one exists — a later check gives this film one and reads red.
body "$H/f/$FILM?as=$OWNER" | grep -q -- "--accent:#5E9B3C" \
  && ok "a mark picked on the Mac reaches the film's page before any refresh" \
  || no "a mark picked on the Mac reaches the film's page before any refresh" "default accent"
body "$H/f/$FILM/icon.svg?as=$OWNER" | grep -q "5E9B3C" \
  && ok "…and its tab icon" || no "…and its tab icon" "no icon in that colour"

# **`/version` says the commit the deploy was stamped with**, on every host
# and to nobody in particular — `hub/deploy.sh` passes it the way this run
# does, as a var on the command. `hub/drift.sh` reads it live.
got=$(body "$H/version")
echo "$got" | grep -q '"commit":"checking-commit"' && ok "version says the commit it was stamped with" || no "version says the commit it was stamped with" "$got"
echo "$got" | grep -q '"deployed":"2026-01-01T00:00:00Z"' && ok "and when it went up" || no "and when it went up" "$got"

got=$(body "$H/whoami?as=$DIRECTOR")
echo "$got" | grep -q "$DIRECTOR" && ok "whoami says who it thinks you are" || no "whoami says who it thinks you are" "$got"

# ---- what you may see -------------------------------------------------------
got=$(body "$H/?as=$OWNER")
echo "$got" | grep -q "Call Her Back" && ok "he sees the film with no list of people at all" || no "he sees the film with no list of people at all" "not listed"

got=$(body "$H/?as=$STRANGER")
echo "$got" | grep -q "No projects" && ok "a stranger sees an empty screen, not a refusal" || no "a stranger sees an empty screen, not a refusal" "saw something"

[ "$(code "$H/f/$FILM?as=$STRANGER")" = 403 ] && ok "a stranger cannot open the film" || no "a stranger cannot open the film" "not 403"

# ---- the Film Set Objects pack, for the Diagrams page (Ref 1216) ------------
# One picture of it in the bucket's `fso/`, served beside a film to whoever
# can open that film and to nobody else — his licence allows plots online,
# not handing out the pictures.
put "fso/arri-150.png" "$HERE/../engine/assets/fso/arri-150.png"
got=$(curl -s -o /dev/null -w "%{http_code} %{content_type}" "$H/f/$FILM/fso/arri-150.png?as=$OWNER")
[ "$got" = "200 image/png" ] && ok "a plan's pack picture comes beside the film" || no "a plan's pack picture comes beside the film" "$got"
[ "$(code "$H/f/$FILM/fso/arri-150.png?as=$STRANGER")" = 403 ] && ok "…and not to a stranger" || no "…and not to a stranger" "not 403"
[ "$(code "$H/f/$FILM/fso/not-in-the-pack.png?as=$OWNER")" = 404 ] && ok "…a name the pack does not have is nothing" || no "…a name the pack does not have is nothing" "not 404"
[ "$(code "$H/f/$FILM/fso/Arri%2F150.png?as=$OWNER")" = 400 ] && ok "…and a name that is not a pack name is refused" || no "…and a name that is not a pack name is refused" "not 400"

# ---- the Diagrams page draws: plan edits, an editor's only ------------------
# `PUT api/diagram` keeps a batch of plan edits as a change log in the
# editor's name. A stranger is told no by the server whatever a page draws;
# a batch that says nothing is refused before any engine is started.
DIA='{"scene":"1","ops":[{"op":{"op":"clear"}}]}'
[ "$(code -X PUT -H 'content-type: application/json' -d "$DIA" "$H/f/$FILM/api/diagram?as=$STRANGER")" = 403 ] \
  && ok "a stranger cannot draw on a plan" || no "a stranger cannot draw on a plan" "not 403"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"scene":"1","ops":[]}' "$H/f/$FILM/api/diagram?as=$OWNER")" = 400 ] \
  && ok "…and an empty batch is refused" || no "…and an empty batch is refused" "not 400"
[ "$(code -X GET "$H/f/$FILM/api/diagram?as=$OWNER")" = 405 ] \
  && ok "…and the door only takes edits" || no "…and the door only takes edits" "not 405"

got=$(body "$H/?as=$WORK")
echo "$got" | grep -q "Call Her Back" && ok "his other address is him too" || no "his other address is him too" "not listed"

# ---- setting who may do what ------------------------------------------------
[ "$(code "$H/f/$FILM/api/people?as=$STRANGER")" = 403 ] && ok "a stranger cannot read the list of people" || no "a stranger cannot read the list of people" "not 403"

sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[]}' "$DIRECTOR")
got=$(body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER")
echo "$got" | grep -q "$DIRECTOR" && ok "he can put somebody on the film" || no "he can put somebody on the film" "$got"
echo "$got" | grep -q "$OWNER" && ok "…and he cannot take himself off it" || no "…and he cannot take himself off it" "owner missing"

[ "$(code "$H/f/$FILM?as=$DIRECTOR")" = 200 ] && ok "the director can now open the film" || no "the director can now open the film" "not 200"

# ---- the rule the hub exists to hold ----------------------------------------
[ "$(code "$H/f/$FILM/api/log/0000000000000001-000000000000000a.log?as=$DIRECTOR")" = 200 ] \
  && ok "a viewer may read a change log" || no "a viewer may read a change log" "not 200"

[ "$(code -X PUT -d x "$H/f/$FILM/api/log/0000000000000001-000000000000000a.log?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer's write is refused by the server" || no "a viewer's write is refused by the server" "not 403"

[ "$(code "$H/f/$FILM/api/people?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot see who else is on the film" || no "a viewer cannot see who else is on the film" "not 403"

sent=$(printf '{"people":[{"email":"%s","role":"editor"}],"links":[]}' "$DIRECTOR")
[ "$(code -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot promote themselves" || no "a viewer cannot promote themselves" "not 403"

# ---- secret links -----------------------------------------------------------
KEY="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
HASH=$(printf '%s' "$KEY" | shasum -a 256 | cut -d' ' -f1)
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[{"hash":"%s","role":"viewer","expires":null}]}' "$DIRECTOR" "$HASH")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null

[ "$(code "$H/f/$FILM?k=$KEY")" = 200 ] && ok "a secret link opens the film" || no "a secret link opens the film" "not 200"
[ "$(code "$H/f/$FILM?k=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")" = 403 ] && ok "a wrong key does not" || no "a wrong key does not" "not 403"
[ "$(code -X PUT -d x "$H/f/$FILM/api/log/0000000000000001-000000000000000a.log?k=$KEY")" = 403 ] \
  && ok "a link cannot write either" || no "a link cannot write either" "not 403"

# ---- a link has to survive the page that used it ----------------------------
#
# The key is in the address of the page; the page then asks for change logs at
# addresses that carry no key. Without a cookie every one of those arrives
# anonymous and the film never loads — the page looks fine and is useless.
JAR=$(mktemp)
curl -s -o /dev/null -c "$JAR" "$H/f/$FILM?k=$KEY"
grep -q "hubkey" "$JAR" && ok "using a link hands back a cookie" || no "using a link hands back a cookie" "no cookie set"
[ "$(curl -s -o /dev/null -b "$JAR" -w "%{http_code}" "$H/f/$FILM/api/state")" = 200 ] \
  && ok "…so the film's own requests are recognised" || no "…so the film's own requests are recognised" "not 200"
rm -f "$JAR"


sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[{"hash":"%s","role":"viewer","expires":"2020-01-01"}]}' "$DIRECTOR" "$HASH")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
[ "$(code "$H/f/$FILM?k=$KEY")" = 403 ] && ok "an expired link stops working" || no "an expired link stops working" "not 403"

# ---- switched off, and switched back on -------------------------------------
#
# **The one that ruined links he had already sent.** Turning general access off
# used to delete the link, so turning it on again minted a new address and every
# link out in the world was dead. It is switched off and kept now, and the whole
# point is that the *same* key works again afterwards.
sent=$(printf '{"people":[],"links":[{"hash":"%s","key":"%s","role":"viewer","off":true,"expires":null}]}' "$HASH" "$KEY")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
[ "$(code "$H/f/$FILM?k=$KEY")" = 403 ]   && ok "a link switched off refuses" || no "a link switched off refuses" "not 403"
body "$H/f/$FILM/api/people?as=$OWNER" | grep -q "$KEY"   && ok "but the address is kept, not thrown away" || no "but the address is kept, not thrown away" "key gone"
sent=$(printf '{"people":[],"links":[{"hash":"%s","key":"%s","role":"viewer","off":false,"expires":null}]}' "$HASH" "$KEY")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
[ "$(code "$H/f/$FILM?k=$KEY")" = 200 ]   && ok "and the same link works again when it is switched back on"   || no "and the same link works again when it is switched back on" "not 200"

# **A password does not change the address.** His instruction: whether a link
# asks for a word is a fact about the link, not a different link.
SALT="00112233445566778899aabbccddeeff"
PASS=$(printf '%sopen sesame' "$SALT" | shasum -a 256 | cut -d' ' -f1)
sent=$(printf '{"people":[],"links":[{"hash":"%s","key":"%s","role":"viewer","off":false,"expires":null,"salt":"%s","pass":"%s"}]}' "$HASH" "$KEY" "$SALT" "$PASS")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
body "$H/f/$FILM/api/people?as=$OWNER" | grep -q "$KEY"   && ok "putting a password on a link leaves its address alone"   || no "putting a password on a link leaves its address alone" "key changed"

# ---- the Projects Console's door ----------------------------------------------
#
# The console never writes into the portal itself; it knocks here, with the
# relay's token and no browser (`consoleDoor` in src/worker.js, 2026-09-15).
# Three switches, each read back and each felt by the person it is for: the
# page comes down for a viewer and a link and stays up for him; a link is
# switched off and its address kept; a page is hidden and shown again. The
# records it writes are the ones the Share page and the Visibility panel
# write, so the last check reads one back through the page's own door.
CONSOLE=(-H "Authorization: Bearer checking-token-not-a-secret")
[ "$(code "$H/console/$FILM")" = 401 ] && ok "the console's door refuses with no token" || no "the console's door refuses with no token" "not 401"
[ "$(code -H "Authorization: Bearer wrong" "$H/console/$FILM")" = 401 ] && ok "…and with the wrong one" || no "…and with the wrong one" "not 401"
[ "$(code "${CONSOLE[@]}" "$H/console/zzzz")" = 404 ] && ok "…and names no film it cannot find" || no "…and names no film it cannot find" "not 404"
# The server's Export for the Mac and phone (exporting.js): behind the token, and a
# project it cannot find is said in words rather than drawn.
[ "$(code -X POST -d '{}' "$H/console/studio/export/0123456789abcdef0123456789abcdef")" = 401 ] \
  && ok "the server's export wants the console's token" || no "the server's export wants the console's token" "not 401"
body "${CONSOLE[@]}" -X POST -d '{}' "$H/console/studio/export/0123456789abcdef0123456789abcdef" | grep -q "No project has that ID" \
  && ok "…and says when no project has the ID" || no "…and says when no project has the ID" "$(body "${CONSOLE[@]}" -X POST -d '{}' "$H/console/studio/export/0123456789abcdef0123456789abcdef" | head -c 200)"

# The film as the checks above left it, plus a viewer and a plain link.
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[{"hash":"%s","key":"%s","role":"viewer","off":false,"expires":null,"note":"for the producer"}],"invites":[]}' "$DIRECTOR" "$HASH" "$KEY")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
got=$(body "${CONSOLE[@]}" "$H/console/$FILM")
echo "$got" | grep -q '"title":"Call Her Back"' && echo "$got" | grep -q '"down":false' \
  && echo "$got" | grep -q "\"keyed\":\"https://share.your-domain.example/f/$FILM?k=$KEY\"" \
  && ok "one call reads the switchboard's row: title, down, the link's address" \
  || no "one call reads the switchboard's row: title, down, the link's address" "$got"

# ---- the friendly address ---------------------------------------------------
#
# His instruction, 2026-09-19: `share.your-domain.example/hla`, for every
# film, and nothing already sent out may break. A short name is the film's
# initials, made the first time anybody looks; it stands for the general link,
# so it obeys that link — off, expired, a password — and a new name keeps the
# old one as an alias.
SHARE=(-H "x-hub-host: share.your-domain.example")
echo "$got" | grep -q '"short":"chb"' && echo "$got" | grep -q '"url":"https://share.your-domain.example/chb"' \
  && ok "the film's link is its initials: share.…/chb" || no "the film's link is its initials: share.…/chb" "$got"
[ "$(code "${SHARE[@]}" "$H/chb")" = 200 ] && ok "the short name opens the film with no key on it" || no "the short name opens the film with no key on it" "$(code "${SHARE[@]}" "$H/chb")"
[ "$(code "${SHARE[@]}" "$H/chb/shotlist")" = 200 ] && ok "…and its pages" || no "…and its pages" "not 200"
[ "$(code "${SHARE[@]}" "$H/chb/api/state")" = 200 ] && ok "…and the film's own requests" || no "…and the film's own requests" "not 200"
[ "$(code "${SHARE[@]}" "$H/f/$FILM?k=$KEY")" = 200 ] && ok "the keyed address he already sent still opens" || no "the keyed address he already sent still opens" "not 200"
[ "$(code "${SHARE[@]}" "$H/callherback?k=$KEY")" = 200 ] && ok "…and the one under the film's title" || no "…and the one under the film's title" "not 200"
JAR=$(mktemp)
curl -s -o /dev/null -c "$JAR" "${SHARE[@]}" "$H/chb"
grep -q "hubkey" "$JAR" && ok "the short name hands back the cookie, so the program inside loads" || no "the short name hands back the cookie" "no cookie set"
rm -f "$JAR"

# ---- the share link may draw on the plans unless he switches it off ---------
# Ruling 2026-10-18: Editable by Link is on by default. With no stored choice a
# share-host visitor reaches the engine (an empty batch is answered 400, which a
# refusal never is); an explicit off refuses them (403); the switch is an
# editor's alone and works both ways; the same key on the main address is
# still a viewer.
PUTJ=(-X PUT -H 'content-type: application/json')
[ "$(code "${PUTJ[@]}" "${SHARE[@]}" -d '{"scene":"1","ops":[]}' "$H/f/$FILM/api/diagram?k=$KEY")" = 400 ] \
  && ok "no stored choice: a link holder gets past the door (on by default)" || no "no stored choice: a link holder gets past the door (on by default)" "not 400"
body "${SHARE[@]}" "$H/f/$FILM/api/diagram/settings?k=$KEY" | grep -q '"linkMay":true' \
  && ok "…and is told they may" || no "…and is told they may" "$(body "${SHARE[@]}" "$H/f/$FILM/api/diagram/settings?k=$KEY")"
[ "$(code "${PUTJ[@]}" -d '{"publicEdit":false}' "$H/f/$FILM/api/diagram/settings?as=$OWNER")" = 200 ] \
  && ok "an editor switches the share link off" || no "an editor switches the share link off" "not 200"
[ "$(code "${PUTJ[@]}" "${SHARE[@]}" -d "$DIA" "$H/f/$FILM/api/diagram?k=$KEY")" = 403 ] \
  && ok "explicit off, a link holder cannot draw on a plan" || no "explicit off, a link holder cannot draw on a plan" "not 403"
body "${SHARE[@]}" "$H/f/$FILM/api/diagram/settings?k=$KEY" | grep -q '"linkMay":false' \
  && ok "…and is told the link is view only" || no "…and is told the link is view only" "$(body "${SHARE[@]}" "$H/f/$FILM/api/diagram/settings?k=$KEY")"
[ "$(code "${PUTJ[@]}" "${SHARE[@]}" -d '{"publicEdit":true}' "$H/f/$FILM/api/diagram/settings?k=$KEY")" = 403 ] \
  && ok "a link holder cannot open the switch themselves" || no "a link holder cannot open the switch themselves" "not 403"
[ "$(code "${PUTJ[@]}" -d '{"publicEdit":true}' "$H/f/$FILM/api/diagram/settings?as=$STRANGER")" = 403 ] \
  && ok "…nor can a stranger" || no "…nor can a stranger" "not 403"
[ "$(code "${PUTJ[@]}" -d '{"publicEdit":true}' "$H/f/$FILM/api/diagram/settings?as=$OWNER")" = 200 ] \
  && ok "an editor opens the share link for drawing" || no "an editor opens the share link for drawing" "not 200"
body "${SHARE[@]}" "$H/f/$FILM/api/diagram/settings?k=$KEY" | grep -q '"linkMay":true' \
  && ok "…and the link's visitor is told they may" || no "…and the link's visitor is told they may" "$(body "${SHARE[@]}" "$H/f/$FILM/api/diagram/settings?k=$KEY")"
[ "$(code "${PUTJ[@]}" "${SHARE[@]}" -d '{"scene":"1","ops":[]}' "$H/f/$FILM/api/diagram?k=$KEY")" = 400 ] \
  && ok "on, a share-host visitor gets past the door" || no "on, a share-host visitor gets past the door" "not 400"
[ "$(code "${PUTJ[@]}" -d "$DIA" "$H/f/$FILM/api/diagram?k=$KEY")" = 403 ] \
  && ok "…but the same key on the main address is still only a viewer" || no "…but the same key on the main address is still only a viewer" "not 403"
[ "$(code "${PUTJ[@]}" -d '{"publicEdit":false}' "$H/f/$FILM/api/diagram/settings?as=$OWNER")" = 200 ] \
  && [ "$(code "${PUTJ[@]}" "${SHARE[@]}" -d "$DIA" "$H/f/$FILM/api/diagram?k=$KEY")" = 403 ] \
  && ok "switched off again, the link is refused again" || no "switched off again, the link is refused again" "not 403"
body "${SHARE[@]}" "$H/chb" | grep -q '"short":"chb","friendly":true' \
  && ok "the page is told its short name, so Copy link is the friendly one" || no "the page is told its short name" "not in HUB"
[ "$(code "${SHARE[@]}" "$H/chb?k=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")" = 404 ] \
  && ok "a wrong key on the short name is judged as itself, not let in" || no "a wrong key on the short name is judged as itself" "not 404"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"short":"demo"}' "$H/console/$FILM/short")" = 200 ] && ok "the console can rename it" || no "the console can rename it" "not 200"
[ "$(code "${SHARE[@]}" "$H/demo")" = 200 ] && [ "$(code "${SHARE[@]}" "$H/chb")" = 200 ] \
  && ok "…and the old name still opens beside the new" || no "…and the old name still opens beside the new" "$(code "${SHARE[@]}" "$H/demo") $(code "${SHARE[@]}" "$H/chb")"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"short":"demo"}' "$H/console/0000000000000000000000000000000f/short")" = 409 ] \
  && ok "a name another film holds is refused" || no "a name another film holds is refused" "not 409"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"short":"callherback"}' "$H/console/0000000000000000000000000000000f/short")" = 409 ] \
  && ok "…and so is another film's title" || no "…and so is another film's title" "not 409"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"short":"decks"}' "$H/console/$FILM/short")" = 400 ] \
  && ok "…and the hub's own addresses are" || no "…and the hub's own addresses are" "not 400"
[ "$(code "$H/demo?as=$DIRECTOR")" = 200 ] && ok "on the signed-in host the short name is a plain address" || no "on the signed-in host the short name is a plain address" "not 200"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"short":"nope"}' "$H/f/$FILM/api/short?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot rename it" || no "a viewer cannot rename it" "not 403"

# Down, and back up — without the film going anywhere.
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"down":true,"by":"console"}' "$H/console/$FILM/down")" = 200 ] \
  && ok "the console can take the page down" || no "the console can take the page down" "not 200"
[ "$(code "$H/f/$FILM?as=$DIRECTOR")" = 503 ] && ok "…and a viewer gets 'This page is down'" || no "…and a viewer gets 'This page is down'" "not 503"
body "$H/f/$FILM?as=$DIRECTOR" | grep -q "This page is down" && ok "…in those words" || no "…in those words" "other words"
[ "$(code "$H/f/$FILM/shotlist?as=$DIRECTOR")" = 503 ] && ok "…at every address under the film" || no "…at every address under the film" "not 503"
[ "$(code "$H/f/$FILM/api/state?as=$DIRECTOR")" = 503 ] && ok "…including the film's own requests" || no "…including the film's own requests" "not 503"
[ "$(code -H "x-hub-host: share.your-domain.example" "$H/f/$FILM?k=$KEY")" = 503 ] \
  && ok "…and for a link holder on the share host" || no "…and for a link holder on the share host" "not 503"
[ "$(code "$H/f/$FILM?as=$OWNER")" = 200 ] && ok "…while he still sees the film himself" || no "…while he still sees the film himself" "not 200"
body "$H/f/$FILM/api/manifest?as=$OWNER" | grep -q "Call Her Back" && ok "…and the film is still there, untouched" || no "…and the film is still there, untouched" "manifest gone"
body "${CONSOLE[@]}" "$H/console/$FILM/down" | grep -q '"down":true' && ok "…and the door reads the flag back" || no "…and the door reads the flag back" "not down"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"down":false}' "$H/console/$FILM/down")" = 200 ] \
  && [ "$(code "$H/f/$FILM?as=$DIRECTOR")" = 200 ] \
  && ok "and the page comes back up for everyone" || no "and the page comes back up for everyone" "still down"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"down":"yes"}' "$H/console/$FILM/down")" = 400 ] \
  && ok "…and a flag that is not true or false is refused" || no "…and a flag that is not true or false is refused" "not 400"

# The share link, off and on, through the same record the Share page writes.
put=$(body -X PUT "${CONSOLE[@]}" -d "{\"hash\":\"$HASH\",\"off\":true}" "$H/console/$FILM/link")
echo "$put" | grep -q '"changed":1' && [ "$(code "$H/f/$FILM?k=$KEY")" = 403 ] \
  && ok "the console can switch the share link off" || no "the console can switch the share link off" "$put — then $(code "$H/f/$FILM?k=$KEY")"
body "$H/f/$FILM/api/people?as=$OWNER" | grep -q "for the producer" \
  && ok "…and the link keeps its address and its note" || no "…and the link keeps its address and its note" "note gone"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"off":false}' "$H/console/$FILM/link")" = 200 ] \
  && [ "$(code "$H/f/$FILM?k=$KEY")" = 200 ] \
  && ok "…and back on, every link at once when none is named" || no "…and back on, every link at once when none is named" "still off"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"hash":"0000000000000000000000000000000000000000000000000000000000000000","off":true}' "$H/console/$FILM/link")" = 404 ] \
  && ok "…and a hash that is nobody's is refused" || no "…and a hash that is nobody's is refused" "not 404"

# Pages hidden and shown, keeping what it was not asked about.
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"crew":["Somebody Quiet"]}' "$H/console/$FILM/visible")" = 200 ] \
  && [ "$(code -X PUT "${CONSOLE[@]}" -d '{"sections":["locations"]}' "$H/console/$FILM/visible")" = 200 ] \
  && [ "$(code "$H/f/$FILM/locations?as=$DIRECTOR")" = 404 ] \
  && ok "the console can hide a page" || no "the console can hide a page" "still answers"
[ "$(code "$H/f/$FILM/locations?as=$OWNER")" = 200 ] && ok "…not from him" || no "…not from him" "hidden from him too"
got=$(body "${CONSOLE[@]}" "$H/console/$FILM/visible")
echo "$got" | grep -q '"crew":\["Somebody Quiet"\]' && echo "$got" | grep -q '"sections":\["locations"\]' \
  && ok "…and a list it was not asked about is kept" || no "…and a list it was not asked about is kept" "$got"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"sections":[],"crew":[]}' "$H/console/$FILM/visible")" = 200 ] \
  && [ "$(code "$H/f/$FILM/locations?as=$DIRECTOR")" = 200 ] \
  && ok "…and shown again" || no "…and shown again" "still hidden"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"sections":"locations"}' "$H/console/$FILM/visible")" = 400 ] \
  && ok "…and a list that is not a list is refused" || no "…and a list that is not a list is refused" "not 400"

# ---- the console as his front door to the portal (2026-10-05) ------------------
# Share (people, roles, the link, its password, a new link), What Viewers See
# and the Library, through `/access`, `/viewers` and `/library` — the portal's
# own rules (`changeAccess`, `saveViewersSee`, `arrangeLibrary`), on a film of
# its own so nothing above or below this is disturbed.
SFILM="0000000000000000000000000000c5a1"
SD=$(mktemp -d)
printf '{"format":1,"project":"%s","title":"Share Door","engine":"0.1.0"}' "$SFILM" > "$SD/manifest.json"
printf 'shotlister-log 1\n' > "$SD/one.log"
printf '[{"t":"p","r":[{"s":"Notes for the door."}]}]' > "$SD/notes.json"
printf '{"version":1,"logline":"A door.","sections":[{"slug":"notes","name":"Notes","by":"here","type":"page","source":"here"},{"slug":"look","name":"Look Board","type":"board","share":"link"}],"documents":[{"name":"Call sheet","url":"https://drive.google.com/y","kind":"document"}],"crew":[{"name":"Ellis Ward","role":"Gaffer","phone":"555 0100"}],"credits":[{"role":"Executive Producer","people":["Owen Fairweather","Tess Marlow"]},{"role":"<b>x","people":["y"]}],"groups":[{"name":"Paper","rows":["notes","look","documents"]}]}' > "$SD/front.json"
put "p/$SFILM/manifest.json" "$SD/manifest.json"
put "p/$SFILM/logs/0000000000000001-00000000000000c5.log" "$SD/one.log"
put "p/$SFILM/pages/notes.json" "$SD/notes.json"
put "p/$SFILM/front.json" "$SD/front.json"
rm -rf "$SD"
A="$H/console/$SFILM/access"
access() { curl -s -X PUT "${CONSOLE[@]}" -d "$1" "$A"; }
accessc() { code -X PUT "${CONSOLE[@]}" -d "$1" "$A"; }
jget() { python3 -c "import json,sys; v=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1" 2>/dev/null; }

# **Every credit the card lists, said the portal's way** (2026-10-05) — and
# a role that is not a few plain words never reaches the page.
got=$(body "$H/f/$SFILM?as=$OWNER")
echo "$got" | grep -q 'Executive Producer <em>Owen Fairweather &amp; Tess Marlow</em>' && ! echo "$got" | grep -q '<b>x' \
  && ok "the film's page lists the other credits, A & B" || no "the film's page lists the other credits, A & B" "not drawn"

# Who may open it.
[ "$(code -X PUT -d '{"add":[]}' "$A")" = 401 ] && ok "the console's Share refuses with no token" || no "the console's Share refuses with no token" "not 401"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"add":[{"email":"a@b.c"}]}' "$H/console/0000000000000000000000000000dead/access")" = 404 ] \
  && ok "…and names no film it cannot find" || no "…and names no film it cannot find" "not 404"
[ "$(code "$H/f/$SFILM?as=$DIRECTOR")" = 403 ] || no "seeding: the door's film is nobody else's yet" "not 403"
got=$(access "{\"add\":[{\"email\":\"$DIRECTOR\",\"role\":\"viewer\"}]}")
echo "$got" | grep -q "added $DIRECTOR" && [ "$(code "$H/f/$SFILM?as=$DIRECTOR")" = 200 ] \
  && ok "the console adds a person by email, and they can open it" || no "the console adds a person by email, and they can open it" "$got"
echo "$got" | grep -q "{\"email\":\"$OWNER\",\"role\":\"editor\",\"owner\":true}" \
  && ok "…and he is on the list as Owner, without being sent" || no "…and he is on the list as Owner, without being sent" "$got"
c=$(accessc "{\"add\":[{\"email\":\"$DIRECTOR\"}]}")
[ "$c" = 409 ] && ok "…somebody already on it is refused" || no "…somebody already on it is refused" "not 409"
[ "$(accessc '{"add":[{"email":"not an address"}]}')" = 400 ] && ok "…and an address that is not one" || no "…and an address that is not one" "not 400"
[ "$(accessc '{"add":[{"email":"x@example.com","role":"owner"}]}')" = 400 ] && ok "…and a role that is not Viewer or Editor" || no "…and a role that is not Viewer or Editor" "not 400"
[ "$(accessc '{"add":{"email":"x@example.com"}}')" = 400 ] && [ "$(accessc '{}')" = 400 ] && [ "$(accessc 'not json')" = 400 ] \
  && ok "…and a list that is not a list, nothing, and not JSON" || no "…and a list that is not a list, nothing, and not JSON" "not 400"
got=$(access "{\"role\":[{\"email\":\"$DIRECTOR\",\"role\":\"editor\"}]}")
echo "$got" | grep -q "{\"email\":\"$DIRECTOR\",\"role\":\"editor\"}" && ok "the console changes a person's role" || no "the console changes a person's role" "$got"
c=$(accessc "{\"role\":[{\"email\":\"$OWNER\",\"role\":\"viewer\"}]}")
[ "$c" = 403 ] && ok "…but never his" || no "…but never his" "not 403"
[ "$(accessc '{"role":[{"email":"nobody.here@example.com","role":"viewer"}]}')" = 404 ] && ok "…nor somebody not on the list" || no "…nor somebody not on the list" "not 404"
got=$(access "{\"remove\":[\"$DIRECTOR\"]}")
echo "$got" | grep -q "removed $DIRECTOR" && [ "$(code "$H/f/$SFILM?as=$DIRECTOR")" = 403 ] \
  && ok "the console removes a person, and they cannot open it now" || no "the console removes a person, and they cannot open it now" "$got"
c=$(accessc "{\"remove\":[\"$WORK\"]}")
[ "$c" = 403 ] && ok "…and will not remove him, by either address" || no "…and will not remove him, by either address" "not 403"

# The link: made on the Mac, sent as its key and hash, replacing whatever was.
K1="consoleKeyOne_aaaaaaaaaaaaaaaaaaaaaaa"
H1=$(printf '%s' "$K1" | shasum -a 256 | cut -d' ' -f1)
K2="consoleKeyTwo-bbbbbbbbbbbbbbbbbbbbbbb"
H2=$(printf '%s' "$K2" | shasum -a 256 | cut -d' ' -f1)
# A short name for a film with no general link stands for nothing, and says
# so (2026-10-13: /zed and /joe answered "No such page").
notshared() { [ "$(code "${SHARE[@]}" "$H/$1")" = 404 ] && body "${SHARE[@]}" "$H/$1" | grep -q "<title>This film isn&#39;t shared"; }
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"short":"quiet"}' "$H/console/$SFILM/short")" = 200 ] && notshared quiet \
  && ok "a private film's short name says it isn't shared" || no "a private film's short name says it isn't shared" "$(body "${SHARE[@]}" "$H/quiet" | grep -o '<title>[^<]*')"
[ "$(accessc '{"link":"anyone"}')" = 409 ] && ok "General Access with no link yet asks for one, it does not make one" || no "General Access with no link yet asks for one" "not 409"
c=$(accessc "{\"replace\":{\"key\":\"$K1\",\"hash\":\"$H1\"}}")
[ "$c" = 400 ] && ok "…a new link must say which it replaces" || no "…a new link must say which it replaces" "not 400"
c=$(accessc "{\"replace\":{\"key\":\"$K1\",\"hash\":\"$H2\",\"was\":null}}")
[ "$c" = 400 ] && ok "…and a hash that is not its key's is refused" || no "…and a hash that is not its key's is refused" "not 400"
c=$(accessc "{\"replace\":{\"key\":\"short\",\"hash\":\"$H1\",\"was\":null}}")
[ "$c" = 400 ] && ok "…and so is a key of the wrong shape" || no "…and so is a key of the wrong shape" "not 400"
got=$(access "{\"replace\":{\"key\":\"$K1\",\"hash\":\"$H1\",\"was\":null}}")
echo "$got" | grep -q "\"hash\":\"$H1\"" && [ "$(code "${SHARE[@]}" "$H/f/$SFILM?k=$K1")" = 200 ] \
  && ok "the console makes the link, and it opens the film" || no "the console makes the link, and it opens the film" "$got"
[ "$(code "${SHARE[@]}" "$H/quiet")" = 200 ] && ok "…and its short name opens it now" || no "…and its short name opens it now" "$(code "${SHARE[@]}" "$H/quiet")"
body "${CONSOLE[@]}" "$H/console/$SFILM/people" | grep -q "\"key\":\"$K1\"" \
  && ok "…its key kept, so Copy Link works on the portal too" || no "…its key kept, so Copy Link works on the portal too" "no key"
c=$(accessc "{\"replace\":{\"key\":\"$K2\",\"hash\":\"$H2\",\"was\":null}}")
[ "$c" = 409 ] \
  && ok "…a replacement naming the wrong link is refused" || no "…a replacement naming the wrong link is refused" "not 409"
got=$(access "{\"replace\":{\"key\":\"$K2\",\"hash\":\"$H2\",\"was\":\"$H1\"}}")
echo "$got" | grep -q "a new link replaces the old one" && [ "$(code "${SHARE[@]}" "$H/f/$SFILM?k=$K1")" = 404 ] && [ "$(code "${SHARE[@]}" "$H/f/$SFILM?k=$K2")" = 200 ] \
  && ok "Replaces the old link: the new one opens, the old one does not" || no "Replaces the old link: the new one opens, the old one does not" "$got"
got=$(access '{"link":"restricted"}')
echo "$got" | grep -q '"off":true' && [ "$(code "${SHARE[@]}" "$H/f/$SFILM?k=$K2")" = 404 ] \
  && ok "General Access Restricted switches the link off" || no "General Access Restricted switches the link off" "$got"
notshared quiet && ok "…and the short name says it isn't shared" || no "…and the short name says it isn't shared" "$(body "${SHARE[@]}" "$H/quiet" | grep -o '<title>[^<]*')"
[ "$(accessc '{"password":null}')" = 409 ] && ok "…and a link that is off takes no password" || no "…and a link that is off takes no password" "not 409"
[ "$(accessc '{"link":"anyone"}')" = 200 ] && [ "$(code "${SHARE[@]}" "$H/f/$SFILM?k=$K2")" = 200 ] \
  && ok "…and Anyone with the Link turns the same link back on" || no "…and Anyone with the Link turns the same link back on" "still off"
[ "$(accessc '{"link":"everyone"}')" = 400 ] && ok "…and General Access is Restricted or Anyone, nothing else" || no "…and General Access is Restricted or Anyone" "not 400"

# The password: made on the Mac, salt and hash; the word never travels.
CSALT="0123456789abcdef0123456789abcdef"
CPASS=$(printf '%s%s' "$CSALT" "door word" | shasum -a 256 | cut -d' ' -f1)
[ "$(accessc '{"password":"door word"}')" = 400 ] && ok "the console may not send a password as the word" || no "the console may not send a password as the word" "not 400"
[ "$(accessc '{"password":{"salt":"xyz","pass":"abc"}}')" = 400 ] && ok "…nor a salt and hash of the wrong shape" || no "…nor a salt and hash of the wrong shape" "not 400"
got=$(access "{\"password\":{\"salt\":\"$CSALT\",\"pass\":\"$CPASS\"}}")
echo "$got" | grep -q '"password":true' && body "${SHARE[@]}" "$H/f/$SFILM?k=$K2" | grep -q "Password" \
  && ok "the console sets the link's password, and the link asks for it" || no "the console sets the link's password, and the link asks for it" "$got"
[ "$(code "${SHARE[@]}" -X POST --data-urlencode "password=door word" "$H/f/$SFILM?k=$K2")" = 303 ] \
  && [ "$(code "${SHARE[@]}" -X POST --data-urlencode "password=wrong" "$H/f/$SFILM?k=$K2")" = 401 ] \
  && ok "…the word made on the Mac opens it, and no other" || no "…the word made on the Mac opens it, and no other" "gate"
! body "${CONSOLE[@]}" "$H/console/$SFILM/people" | grep -q "door word" && ok "…and the word is nowhere in the list" || no "…and the word is nowhere in the list" "stored"
[ "$(accessc '{"password":null}')" = 200 ] && [ "$(code "${SHARE[@]}" "$H/f/$SFILM?k=$K2")" = 200 ] \
  && ok "…and cleared, the link opens without one" || no "…and cleared, the link opens without one" "still asks"

# Compare-and-set: a change made from a list read earlier lands only if nobody wrote since.
ETAG=$(body "${CONSOLE[@]}" "$H/console/$SFILM/people" | jget "v['etag']")
[ -n "$ETAG" ] && [ "$(body "${CONSOLE[@]}" "$H/console/$SFILM" | jget "v['people_etag']")" = "$ETAG" ] \
  && ok "the list carries its tag, in the readout too" || no "the list carries its tag, in the readout too" "$ETAG"
c=$(accessc "{\"add\":[{\"email\":\"first@example.com\"}],\"if_match\":\"$ETAG\"}")
[ "$c" = 200 ] \
  && ok "…a change made over the list as read lands" || no "…a change made over the list as read lands" "not 200"
c=$(accessc "{\"add\":[{\"email\":\"second@example.com\"}],\"if_match\":\"$ETAG\"}")
[ "$c" = 409 ] \
  && ! body "${CONSOLE[@]}" "$H/console/$SFILM/people" | grep -q "second@example.com" \
  && ok "…one made over the same, now old, list is refused and writes nothing" || no "…one made over the same, now old, list is refused" "not 409"
body "${CONSOLE[@]}" "$H/console/$SFILM/people" | grep -q "first@example.com" \
  && ok "…and the first change is still there" || no "…and the first change is still there" "lost"
access '{"remove":["first@example.com"]}' >/dev/null

# What Viewers See: ticked is seen, through the panel's own save.
V="$H/console/$SFILM/viewers"
access "{\"add\":[{\"email\":\"$DIRECTOR\",\"role\":\"viewer\"}]}" >/dev/null
got=$(body "${CONSOLE[@]}" "$V")
echo "$got" | grep -q '{"at":"notes","name":"Notes","shown":true}' && echo "$got" | grep -q '"at":"look","name":"Look Board","board":true,"share":"link","shown":true' \
  && echo "$got" | grep -q '{"name":"Ellis Ward","shown":true,"contact":false}' && echo "$got" | grep -q '{"name":"Call sheet","shown":true}' \
  && ok "the console reads What Viewers See: sections, people, documents" || no "the console reads What Viewers See" "$got"
SHOWN=$(echo "$got" | jget "json.dumps([s['at'] for s in v['sections'] if s['at'] not in ('notes','look')])")
c=$(code -X PUT "${CONSOLE[@]}" -d "{\"sections\":$SHOWN}" "$V")
[ "$c" = 200 ] && [ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 404 ] \
  && [ "$(code "$H/f/$SFILM/notes?as=$OWNER")" = 200 ] \
  && ok "…a page left unticked is Private: gone for a viewer, not for him" || no "…a page left unticked is Private" "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")"
body "${CONSOLE[@]}" "$V" | grep -q '"at":"look","name":"Look Board","board":true,"share":"crew","shown":false' \
  && ok "…and a board unticked goes back to the crew, as the panel does it" || no "…and a board unticked goes back to the crew" "$(body "${CONSOLE[@]}" "$V")"
body "$H/f/$SFILM/visibility?as=$OWNER" | grep -q 'name="sections" value="notes" aria-label' \
  && ok "…and the portal's own panel shows it unticked" || no "…and the portal's own panel shows it unticked" "ticked"
got=$(body -X PUT "${CONSOLE[@]}" -d '{"crew":[],"contact":["Ellis Ward"]}' "$V")
echo "$got" | grep -q '{"name":"Ellis Ward","shown":false,"contact":true}' && echo "$got" | grep -q '{"at":"notes","name":"Notes","shown":false}' \
  && ok "…People: Shown and Contact, and a list not sent is kept" || no "…People: Shown and Contact, and a list not sent is kept" "$got"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"documents":"Call sheet"}' "$V")" = 400 ] && [ "$(code -X PUT "${CONSOLE[@]}" -d '{"sections":[1]}' "$V")" = 400 ] \
  && [ "$(code -X PUT "${CONSOLE[@]}" -d '{}' "$V")" = 400 ] && [ "$(code "$V")" = 401 ] \
  && ok "…and a list that is not names, nothing, or no token is refused" || no "…and a list that is not names, nothing, or no token is refused" "not refused"
ALL=$(body "${CONSOLE[@]}" "$V" | jget "json.dumps([s['at'] for s in v['sections']])")
c=$(code -X PUT "${CONSOLE[@]}" -d "{\"sections\":$ALL,\"crew\":[\"Ellis Ward\"],\"contact\":[],\"documents\":[\"Call sheet\"]}" "$V")
[ "$c" = 200 ] \
  && [ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 200 ] && body "${CONSOLE[@]}" "$V" | grep -q '"share":"link","shown":true' \
  && ok "…and everything ticked shows it all again" || no "…and everything ticked shows it all again" "still hidden"

# The Library: Pinned, Private, Archive, per page.
L="$H/console/$SFILM/library"
lib() { code -X PUT "${CONSOLE[@]}" -d "$1" "$L"; }
# One page's or document's settings, whatever else the Library says of it
# (its shelf, kind and icon came later): `libsays notes pinned=true private=false`.
libsays() { body "${CONSOLE[@]}" "$L" | python3 -c 'import json,sys
v=json.load(sys.stdin); k=sys.argv[1]
rows=v["documents"] if k.startswith("doc:") else v["pages"]
r=[x for x in rows if ("doc:"+x["name"] if k.startswith("doc:") else x.get("at"))==k]
sys.exit(0 if r and all(str(r[0].get(a)).lower()==b for a,b in (w.split("=") for w in sys.argv[2:])) else 1)' "$@"; }
libsays notes pinned=true private=false archived=false \
  && ok "the console reads the Library: each page pinned, private, archived" || no "the console reads the Library" "$(body "${CONSOLE[@]}" "$L")"
[ "$(lib '{"keys":["notes"],"action":"unpin"}')" = 200 ] && libsays notes pinned=false \
  && ! body "$H/f/$SFILM?as=$OWNER" | grep -q 'data-key="notes"' \
  && ok "…unpins a page: off the sidebar" || no "…unpins a page: off the sidebar" "still pinned"
[ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 200 ] && ok "…and still at its address" || no "…and still at its address" "gone"
[ "$(lib '{"keys":["notes"],"action":"pin"}')" = 200 ] && body "$H/f/$SFILM?as=$OWNER" | grep -q 'data-key="notes"' \
  && ok "…and pins it back" || no "…and pins it back" "not back"
[ "$(lib '{"keys":["notes"],"action":"private"}')" = 200 ] && [ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 404 ] \
  && [ "$(lib '{"keys":["notes"],"action":"public"}')" = 200 ] && [ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 200 ] \
  && ok "…makes it Private, and public again" || no "…makes it Private, and public again" "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")"
[ "$(lib '{"keys":["notes"],"action":"archive"}')" = 200 ] \
  && libsays notes pinned=false private=true archived=true \
  && [ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 404 ] \
  && ok "…archives it: unpinned and private" || no "…archives it: unpinned and private" "$(body "${CONSOLE[@]}" "$L")"
[ "$(lib '{"keys":["notes"],"action":"unarchive"}')" = 200 ] \
  && libsays notes pinned=true private=false archived=false \
  && [ "$(code "$H/f/$SFILM/notes?as=$DIRECTOR")" = 200 ] \
  && ok "…and unarchives it to exactly what it was" || no "…and unarchives it to exactly what it was" "$(body "${CONSOLE[@]}" "$L")"
[ "$(lib '{"keys":["doc:Call sheet"],"action":"archive"}')" = 200 ] \
  && libsays "doc:Call sheet" private=true archived=true \
  && [ "$(lib '{"keys":["doc:Call sheet"],"action":"unarchive"}')" = 200 ] \
  && libsays "doc:Call sheet" private=false archived=false \
  && ok "…and a document, by its name" || no "…and a document, by its name" "$(body "${CONSOLE[@]}" "$L")"
[ "$(lib '{"keys":["notes"],"action":"dance"}')" = 400 ] && [ "$(lib '{"keys":["notes"],"action":"shelf","to":"no-such-shelf"}')" = 404 ] \
  && [ "$(lib '{"keys":["no-such-page"],"action":"pin"}')" = 404 ] \
  && [ "$(lib '{"keys":"notes","action":"pin"}')" = 400 ] && [ "$(lib '{"keys":["notes"],"action":"rename","to":"Jotter"}')" = 400 ] \
  && [ "$(code -X PUT -d '{"keys":["notes"],"action":"pin"}' "$L")" = 401 ] \
  && ok "…and refuses an action, a page, a list or a caller it does not know" || no "…and refuses an action, a page, a list or a caller it does not know" "not refused"

# ---- the record: one per project, on Cloudflare (Projects Console, 2026-09-15)
# Keyed on the project's Notion page id, written by the Studio, read by any
# device. A pending item is claimed once and only once. And the project's own
# address, /f/<page id>, goes to its film's page — or, with no film yet, to
# the record's own page, for him alone.
PAGE="58831215c4688f529ea9d49ee258a917"
[ "$(code "${CONSOLE[@]}" "$H/console/record/$PAGE")" = 404 ] && ok "a project with no record yet says so" || no "a project with no record yet says so" "not 404"
[ "$(code "${CONSOLE[@]}" "$H/console/record/not-a-page-id")" = 404 ] && ok "…and a key that is not a page id is refused" || no "…and a key that is not a page id is refused" "not 404"
rec=$(printf '{"version":1,"page":"%s","name":"Call Her Back","slug":"call-her-back","stage":"Active","director":"Clara Moreau","lights":{"drive":"on","film":"on"},"film":{"title":"Call Her Back","relay":"%s"}}' "$PAGE" "$FILM")
put=$(body -X PUT "${CONSOLE[@]}" -d "$rec" "$H/console/record/$PAGE")
echo "$put" | grep -q '"updated":"20' && ok "the Studio can write a project's record" || no "the Studio can write a project's record" "$put"
got=$(body "${CONSOLE[@]}" "$H/console/record/$PAGE")
echo "$got" | grep -q '"name":"Call Her Back"' && echo "$got" | grep -q '"updated":"20' \
  && ok "…and any device reads it back, stamped" || no "…and any device reads it back, stamped" "$got"
body "${CONSOLE[@]}" "$H/console/records" | grep -q "\"page\":\"$PAGE\"" && ok "…and it is in the list of records" || no "…and it is in the list of records" "not listed"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"page":"00000000000000000000000000000000","name":"x"}' "$H/console/record/$PAGE")" = 400 ] \
  && ok "…and a record naming a different page is refused" || no "…and a record naming a different page is refused" "not 400"
[ "$(code "$H/console/record/$PAGE")" = 401 ] && ok "…and none of it without the token" || no "…and none of it without the token" "not 401"

# ---- the record's facts: one version each (2026-10-05, the one-record plan)
# What he typed about a project lives in `facts`, each with its own version.
# A write names the version it started from; a stale one is refused with what
# is there now and nothing is written. The console's readout PUT never touches
# facts. Every change is kept in the history.
F="$H/console/record/$PAGE/facts"
one=$(body -X PUT "${CONSOLE[@]}" -d '{"changes":{"logline":{"value":"A cook, a camera, two days.","base":0}},"by":"studio"}' "$F")
echo "$one" | grep -q '"v":1' && echo "$one" | grep -q 'two days' && ok "a fact is written, version 1" || no "a fact is written, version 1" "$one"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"changes":{"logline":{"value":"stale","base":0}},"by":"phone"}' "$F")" = 409 ] \
  && ok "…a write from an old version is refused" || no "…a write from an old version is refused" "not 409"
stale=$(body -X PUT "${CONSOLE[@]}" -d '{"changes":{"logline":{"value":"stale","base":0}},"by":"phone"}' "$F")
echo "$stale" | grep -q '"conflicts"' && echo "$stale" | grep -q 'two days' && ok "…and says what is there now" || no "…and says what is there now" "$stale"
body "${CONSOLE[@]}" "$F" | grep -q 'stale' && no "…and wrote nothing" "the stale value got in" || ok "…and wrote nothing"
two=$(body -X PUT "${CONSOLE[@]}" -d '{"changes":{"logline":{"value":"A cook, a camera, two shoots.","base":1}},"by":"phone"}' "$F")
echo "$two" | grep -q '"v":2' && ok "…a write from the current version goes in as version 2" || no "…a write from the current version goes in as version 2" "$two"
body -X PUT "${CONSOLE[@]}" -d "$(printf '{"version":1,"page":"%s","name":"Call Her Back","slug":"call-her-back","stage":"Active","director":"Clara Moreau","lights":{"drive":"on","film":"on"},"film":{"title":"Call Her Back","relay":"%s"},"facts":{"logline":{"value":"OVERWRITTEN","v":99}}}' "$PAGE" "$FILM")" "$H/console/record/$PAGE" >/dev/null
after=$(body "${CONSOLE[@]}" "$F")
echo "$after" | grep -q 'two shoots' && ! echo "$after" | grep -q OVERWRITTEN \
  && ok "the console's readout never overwrites a fact" || no "the console's readout never overwrites a fact" "$after"
hist=$(body "${CONSOLE[@]}" "$H/console/record/$PAGE/history")
[ "$(echo "$hist" | grep -o '"field":"logline"' | wc -l | tr -d ' ')" = 2 ] && ok "…and every change is kept in the history" || no "…and every change is kept in the history" "$hist"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"changes":{"Bad Name":{"value":1}}}' "$F")" = 400 ] && ok "…a fact needs a plain name" || no "…a fact needs a plain name" "not 400"
[ "$(code "$F")" = 401 ] && ok "…and none of it without the token" || no "…and none of it without the token (facts)" "not 401"

# the project's own address
[ "$(code "$H/f/$PAGE?as=$OWNER")" = 302 ] && [ "$(curl -s -o /dev/null -w '%{redirect_url}' "$H/f/$PAGE/shotlist?k=$KEY&as=$OWNER")" = "$H/f/$FILM/shotlist?k=$KEY&as=$OWNER" ] \
  && ok "/f/<page id> goes to the film's page, path and query kept" || no "/f/<page id> goes to the film's page, path and query kept" "$(code "$H/f/$PAGE?as=$OWNER") $(curl -s -o /dev/null -w '%{redirect_url}' "$H/f/$PAGE/shotlist?k=$KEY&as=$OWNER")"
[ "$(code "$H/f/$FILM?as=$OWNER")" = 200 ] && ok "…while the film's own address is untouched" || no "…while the film's own address is untouched" "not 200"
nofilm=$(printf '{"page":"%s","name":"Oddity","stage":"Development","lights":{"drive":"on"}}' "${PAGE%?}2")
body -X PUT "${CONSOLE[@]}" -d "$nofilm" "$H/console/record/${PAGE%?}2" >/dev/null
[ "$(code "$H/f/${PAGE%?}2?as=$OWNER")" = 200 ] && body "$H/f/${PAGE%?}2?as=$OWNER" | grep -q "No film is attached yet" \
  && ok "a project with no film has a page of its own, for him" || no "a project with no film has a page of its own, for him" "$(code "$H/f/${PAGE%?}2?as=$OWNER")"
[ "$(code "$H/f/${PAGE%?}2?as=$DIRECTOR")" = 403 ] && ok "…and for nobody else" || no "…and for nobody else" "not 403"
[ "$(code "$H/f/${PAGE%?}3?as=$DIRECTOR")" = 403 ] && ok "…and an id with no record is nothing" || no "…and an id with no record is nothing" "not 403"

# ---- a portal with no film behind it (the console's ask, 2026-09-16) ---------
# The project's own address becomes its front of house: the console marks it
# through the door, the page draws for everyone it is shared with, and the
# film's four screens stay off the rail because there is no film.
NOFILM="${PAGE%?}2"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"title":"Oddity"}' "$H/console/$FILM/portal")" = 409 ] \
  && ok "a film's id cannot be marked as a portal on its own" || no "a film's id cannot be marked as a portal on its own" "not 409"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"title":"Oddity"}' "$H/console/0123456789abcdef/portal")" = 400 ] \
  && ok "…nor an id that is not a project's page id" || no "…nor an id that is not a project's page id" "not 400"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"title":""}' "$H/console/$NOFILM/portal")" = 400 ] \
  && ok "…nor one with no name" || no "…nor one with no name" "not 400"
made=$(body -X PUT "${CONSOLE[@]}" -d '{"title":"Oddity","by":"console"}' "$H/console/$NOFILM/portal")
echo "$made" | grep -q '"title":"Oddity"' && echo "$made" | grep -q "\"url\":\"https://[^\"]*/f/$NOFILM\"" \
  && ok "the console can make a project's address a portal with no film" || no "the console can make a project's address a portal with no film" "$made"
body "${CONSOLE[@]}" "$H/console/$NOFILM/portal" | grep -q '"page":"'"$NOFILM"'"' && ok "…and the door reads the mark back" || no "…and the door reads the mark back" "no mark"
body "${CONSOLE[@]}" "$H/console/portals" | grep -q "\"project\":\"$NOFILM\"" && ok "…and it is in the list of portals" || no "…and it is in the list of portals" "not listed"
body "${CONSOLE[@]}" "$H/console/$NOFILM" | grep -q '"portal":true' && body "${CONSOLE[@]}" "$H/console/$NOFILM" | grep -q '"title":"Oddity"' \
  && ok "…and the switchboard readout says so, by name" || no "…and the switchboard readout says so, by name" "$(body "${CONSOLE[@]}" "$H/console/$NOFILM")"
body "${CONSOLE[@]}" "$H/console/$FILM" | grep -q '"portal":false' && ok "…while a film's readout says it is a film" || no "…while a film's readout says it is a film" "not false"
[ "$(code "$H/console/$NOFILM/portal")" = 401 ] && ok "…and none of it without the token" || no "…and none of it without the token" "not 401"
got=$(body "$H/f/$NOFILM?as=$OWNER")
[ "$(code "$H/f/$NOFILM?as=$OWNER")" = 200 ] && ! echo "$got" | grep -q "No film is attached yet" && echo "$got" | grep -q 'class="filmname">Oddity' \
  && ok "the project's address is its front of house now" || no "the project's address is its front of house now" "$(code "$H/f/$NOFILM?as=$OWNER")"
! echo "$got" | grep -q 'data-key="shotlist"' && ! echo "$got" | grep -q 'data-key="locations"' && echo "$got" | grep -q '/add"' \
  && ok "…with the film's screens off the rail, and Add as the way to its pages" || no "…with the film's screens off the rail, and Add as the way to its pages" "rail"
echo "$got" | grep -q 'class="hm-props"\|hm-chips' && no "…and its home has no Properties panel or chips" "still drawn" || ok "…and its home has no Properties panel or chips"
[ "$(code "$H/f/$NOFILM/shotlist?as=$OWNER")" = 404 ] && [ "$(code "$H/f/$NOFILM/locations?as=$OWNER")" = 404 ] \
  && ok "…and the film's screens are nothing at their addresses" || no "…and the film's screens are nothing at their addresses" "$(code "$H/f/$NOFILM/shotlist?as=$OWNER")"
[ "$(code "$H/f/$NOFILM/documents?as=$OWNER")" = 200 ] && ok "…while its Documents page opens" || no "…while its Documents page opens" "not 200"
[ "$(code "$H/f/$NOFILM?as=$DIRECTOR")" = 403 ] && ok "it is nobody else's until it is shared" || no "it is nobody else's until it is shared" "not 403"
body -X PUT -H 'content-type: application/json' -d "{\"people\":[{\"email\":\"$DIRECTOR\",\"role\":\"viewer\"}],\"links\":[],\"invites\":[]}" "$H/f/$NOFILM/api/people?as=$OWNER" >/dev/null
[ "$(code "$H/f/$NOFILM?as=$DIRECTOR")" = 200 ] && ok "…and shared the same way as a film" || no "…and shared the same way as a film" "not 200"
body "$H/f/$NOFILM/visibility?as=$OWNER" | grep -q 'value="documents"' && ! body "$H/f/$NOFILM/visibility?as=$OWNER" | grep -q 'value="shotlist"' \
  && ok "…and the visibility panel offers only what it has" || no "…and the visibility panel offers only what it has" "panel"
shelf=$(body "$H/?as=$OWNER")
echo "$shelf" | grep -q "Oddity" && ! echo "$shelf" | grep -q "0 changes" && ok "…and it sits on the shelf, without a count of changes" || no "…and it sits on the shelf, without a count of changes" "shelf"
[ "$(code "$H/oddity?as=$OWNER")" = 200 ] && ok "…and answers to its name" || no "…and answers to its name" "not 200"

# ---- and when a film arrives later, the portal is carried into it -----------
# His ruling, 2026-09-16: "the pages should move across and merge in." A page
# and a document made on the filmless portal, a person it was shared with, a
# hidden row — all of it is the film's once the record names the film, and
# the project's address goes to the film as it always has.
CFILM="0000000000000000000000000000000c"
printf '{"format":1,"project":"%s","title":"Oddity, Filmed","engine":"0.1.0"}' "$CFILM" > /tmp/hubcheck-cfilm.json
printf 'shotlister-log 1\n' > /tmp/hubcheck-cfilm.log
put "p/$CFILM/manifest.json" /tmp/hubcheck-cfilm.json
put "p/$CFILM/logs/0000000000000001-000000000000000c.log" /tmp/hubcheck-cfilm.log
printf '[{"t":"p","r":[{"s":"Prep notes from before the film."}]}]' > /tmp/hubcheck-prep-carry.json
put "p/$NOFILM/pages/prep.json" /tmp/hubcheck-prep-carry.json
printf '{"version":1,"logline":"A portal before its film.","linked":"link","source":"notion:%s","sections":[{"slug":"prep","name":"Prep","by":"here","type":"page","source":"here"}],"documents":[{"name":"Deal memo","url":"https://drive.google.com/x","kind":"document"}],"groups":[{"name":"Paper","rows":["prep","documents"]}]}' "$NOFILM" > /tmp/hubcheck-carry-front.json
put "p/$NOFILM/front.json" /tmp/hubcheck-carry-front.json
printf '{"version":1,"logline":"","sections":[],"documents":[]}' > /tmp/hubcheck-cfilm-front.json
put "p/$CFILM/front.json" /tmp/hubcheck-cfilm-front.json
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"sections":["camera","shotlist","boards"]}' "$H/console/$NOFILM/visible")" = 200 ] || no "seeding: hide a row on the portal" "not 200"
body "$H/f/$NOFILM?as=$OWNER" | grep -q 'data-key="prep"' && ok "the portal on its own draws his page before the film comes" || no "the portal on its own draws his page before the film comes" "no row"
# A page on the portal that follows a Google Doc: the clock's list names it
# under the portal's id, and must name it under the film's once it is carried
# (Halcyon's Outline stopped updating on 2026-10-13 because it did not).
printf '{"version":1,"pages":[{"project":"%s","slug":"prep","version":"7","hash":"h","render":"1"}]}' "$NOFILM" > /tmp/hubcheck-follow-index.json
put "follow/index.json" /tmp/hubcheck-follow-index.json
rec=$(printf '{"version":1,"page":"%s","name":"Oddity","stage":"Active","lights":{"film":"on"},"film":{"title":"Oddity, Filmed","relay":"%s"}}' "$NOFILM" "$CFILM")
put=$(body -X PUT "${CONSOLE[@]}" -d "$rec" "$H/console/record/$NOFILM")
echo "$put" | grep -q '"carried":{' && echo "$put" | grep -q '"people":[1-9]' && echo "$put" | grep -q '"sections":1' && echo "$put" | grep -q '"documents":1' && echo "$put" | grep -q '"hidden":1' && echo "$put" | grep -q '"objects":1' \
  && ok "the record naming a film carries the portal into it, and says what moved" || no "the record naming a film carries the portal into it, and says what moved" "$put"
followed=$(cd "$HERE" && $W r2 object get "shotlister-preview/follow/index.json" --pipe --local --persist-to "$STATE" 2>/dev/null)
echo "$put" | grep -q '"follows":1' && echo "$followed" | grep -q "\"project\":\"$CFILM\"" && ! echo "$followed" | grep -q "\"project\":\"$NOFILM\"" \
  && ok "a followed page goes on being followed, under the film's id" || no "a followed page goes on being followed, under the film's id" "$followed"
[ "$(code "$H/console/$NOFILM/portal")" = 401 ] || true
[ "$(code "${CONSOLE[@]}" "$H/console/$NOFILM/portal")" = 404 ] && ! body "${CONSOLE[@]}" "$H/console/portals" | grep -q "$NOFILM" \
  && ok "…and the portal on its own is gone" || no "…and the portal on its own is gone" "still marked"
[ "$(curl -s -o /dev/null -w '%{redirect_url}' "$H/f/$NOFILM/prep?as=$OWNER")" = "$H/f/$CFILM/prep?as=$OWNER" ] \
  && ok "…and the project's address goes to the film, page and all" || no "…and the project's address goes to the film, page and all" "$(curl -s -o /dev/null -w '%{redirect_url}' "$H/f/$NOFILM/prep?as=$OWNER")"
home=$(body "$H/f/$CFILM?as=$OWNER")
echo "$home" | grep -q 'data-key="prep"' && echo "$home" | grep -q 'class="grouphead"[^>]*>Paper<' && echo "$home" | grep -q "A portal before its film" \
  && ok "the film's page carries his page, his heading and the words" || no "the film's page carries his page, his heading and the words" "rail"
[ "$(code "$H/f/$CFILM/prep?as=$OWNER")" = 200 ] && body "$H/f/$CFILM/prep?as=$OWNER" | grep -q "Prep notes from before the film" \
  && ok "…and the page itself came across" || no "…and the page itself came across" "$(code "$H/f/$CFILM/prep?as=$OWNER")"
body "$H/f/$CFILM/documents?as=$OWNER" | grep -q "Deal memo" && ok "…and the document he pinned" || no "…and the document he pinned" "no document"
[ "$(code "$H/f/$CFILM?as=$DIRECTOR")" = 200 ] && ok "…and the person it was shared with" || no "…and the person it was shared with" "not 200"
# **Boards is read off the stored list, not the rail**, since 2026-09-23: this
# film has no boards, and an empty screen is left off a viewer's rail whatever
# is hidden (`unfilled`). What this proves is that carrying cleared it.
! body "$H/f/$CFILM?as=$DIRECTOR" | grep -q 'data-key="camera"' && body "$H/f/$CFILM?as=$DIRECTOR" | grep -q 'data-key="shotlist"' && ! body "${CONSOLE[@]}" "$H/console/$CFILM/visible" | grep -q '"boards"' \
  && ok "…and what he hid stays hidden, while the film's own screens are back — even ones hidden where they were never offered" || no "…and what he hid stays hidden, while the film's own screens are back — even ones hidden where they were never offered" "rail"
put=$(body -X PUT "${CONSOLE[@]}" -d "$rec" "$H/console/record/$NOFILM")
! echo "$put" | grep -q '"carried"' && ok "a second record carries nothing, because nothing is left" || no "a second record carries nothing, because nothing is left" "$put"

# ---- and the carry can be asked for by name, when the record never learned the id
# Harbour Light Affair, 2026-09-18: the console wrote its record three seconds
# after the film was made, before the film's first sync gave it a relay id,
# and never wrote again — so the two portals stood side by side for a day,
# and a share link he had sent out was keyed on the portal under the film's
# own name. `POST /console/<page>/portal/carry {relay}` is the door for
# whatever learns both ids later (the refresh does, off the film's own
# project link). The link he sent must go on working, under the same name.
NOFILM3="${PAGE%?}3"
CFILM3="0000000000000000000000000000000d"
CKEY="dddddddddddddddddddddddddddddddd"
CHASH=$(printf '%s' "$CKEY" | shasum -a 256 | cut -d' ' -f1)
body -X PUT "${CONSOLE[@]}" -d '{"title":"Crown","by":"console"}' "$H/console/$NOFILM3/portal" >/dev/null
sent=$(printf '{"people":[{"email":"%s","role":"editor"}],"links":[{"hash":"%s","role":"viewer","expires":null}],"invites":[]}' "$OWNER" "$CHASH")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$NOFILM3/api/people?as=$OWNER" >/dev/null
printf '[{"t":"p","r":[{"s":"The teaser and its stills."}]}]' > /tmp/hubcheck-refs-carry.json
put "p/$NOFILM3/pages/references.json" /tmp/hubcheck-refs-carry.json
printf '{"version":1,"logline":"","linked":"link","source":"notion:%s","sections":[{"slug":"references","name":"References","by":"here","type":"page","source":"here"}],"documents":[],"groups":[]}' "$NOFILM3" > /tmp/hubcheck-carry-front3.json
put "p/$NOFILM3/front.json" /tmp/hubcheck-carry-front3.json
[ "$(code -H "x-hub-host: share.your-domain.example" "$H/crown?k=$CKEY")" = 200 ] \
  && ok "a share link under the name opens the portal before its film" || no "a share link under the name opens the portal before its film" "not 200"
[ "$(code -X POST "${CONSOLE[@]}" -d "{\"relay\":\"$CFILM3\"}" "$H/console/$NOFILM3/portal/carry")" = 409 ] \
  && ok "the carry is refused into an id holding no film" || no "the carry is refused into an id holding no film" "not 409"
printf '{"format":1,"project":"%s","title":"Crown","engine":"0.1.0"}' "$CFILM3" > /tmp/hubcheck-cfilm3.json
put "p/$CFILM3/manifest.json" /tmp/hubcheck-cfilm3.json
put "p/$CFILM3/logs/0000000000000001-000000000000000d.log" /tmp/hubcheck-cfilm.log
printf '{"version":1,"people":[{"email":"%s","role":"editor"}],"links":[],"invites":[]}' "$OWNER" > /tmp/hubcheck-cfilm3-people.json
put "p/$CFILM3/people.json" /tmp/hubcheck-cfilm3-people.json
[ "$(code -X POST "${CONSOLE[@]}" -d "{\"relay\":\"$NOFILM3\"}" "$H/console/$NOFILM3/portal/carry")" = 400 ] \
  && ok "…and into itself" || no "…and into itself" "not 400"
[ "$(code -X POST "${CONSOLE[@]}" -d "{\"relay\":\"$CFILM3\"}" "$H/console/$NOFILM/portal/carry")" = 404 ] \
  && ok "…and from an id that is not a portal on its own" || no "…and from an id that is not a portal on its own" "not 404"
put=$(body -X POST "${CONSOLE[@]}" -d "{\"relay\":\"$CFILM3\"}" "$H/console/$NOFILM3/portal/carry")
echo "$put" | grep -q '"carried":{' && echo "$put" | grep -q '"links":1' && echo "$put" | grep -q '"sections":1' && echo "$put" | grep -q '"objects":1' \
  && ok "asked for by name, the carry moves the link, the page and its file" || no "asked for by name, the carry moves the link, the page and its file" "$put"
[ "$(code "${CONSOLE[@]}" "$H/console/$NOFILM3/portal")" = 404 ] && ok "…and the portal on its own is gone" || no "…and the portal on its own is gone" "still marked"
[ "$(code -H "x-hub-host: share.your-domain.example" "$H/crown?k=$CKEY")" = 200 ] \
  && body -H "x-hub-host: share.your-domain.example" "$H/crown?k=$CKEY" | grep -q 'data-key="references"' \
  && ok "the share link he sent out still opens, under the same name, now on the film" || no "the share link he sent out still opens, under the same name, now on the film" "$(code -H "x-hub-host: share.your-domain.example" "$H/crown?k=$CKEY")"
[ "$(code -H "x-hub-host: share.your-domain.example" "$H/crown/references?k=$CKEY")" = 200 ] \
  && ok "…and the page it pointed at" || no "…and the page it pointed at" "$(code -H "x-hub-host: share.your-domain.example" "$H/crown/references?k=$CKEY")"
[ "$(code -X POST "${CONSOLE[@]}" -d "{\"relay\":\"$CFILM3\"}" "$H/console/$NOFILM3/portal/carry")" = 404 ] \
  && ok "a second carry finds nothing to carry" || no "a second carry finds nothing to carry" "not 404"

# pending: asked from anywhere, claimed once, done by the Studio
item=$(body -X POST "${CONSOLE[@]}" -d '{"verb":"portal_down","args":{"down":true},"by":"phone"}' "$H/console/record/$PAGE/pending")
ID=$(printf '%s' "$item" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))')
[ -n "$ID" ] && echo "$item" | grep -q '"state":"pending"' && ok "a device can put a verb on the record as pending" || no "a device can put a verb on the record as pending" "$item"
body "${CONSOLE[@]}" "$H/console/pending" | grep -q "\"id\":\"$ID\"" && body "${CONSOLE[@]}" "$H/console/pending" | grep -q '"name":"Call Her Back"' \
  && ok "…and the Studio sees it across every record, with the project's name" || no "…and the Studio sees it across every record, with the project's name" "not listed"
[ "$(code -X POST "${CONSOLE[@]}" -d '{"verb":"rm -rf"}' "$H/console/record/$PAGE/pending")" = 400 ] && ok "…a verb that is not a word is refused" || no "…a verb that is not a word is refused" "not 400"
claim=$(body -X PUT "${CONSOLE[@]}" -d '{"state":"working","by":"studio"}' "$H/console/record/$PAGE/pending/$ID")
echo "$claim" | grep -q '"state":"working"' && ok "the Studio claims it" || no "the Studio claims it" "$claim"
again=$(body -X PUT "${CONSOLE[@]}" -d '{"state":"working","by":"laptop"}' "$H/console/record/$PAGE/pending/$ID")
echo "$again" | grep -q '"by_done":"studio"' && ! echo "$again" | grep -q '"by_done":"laptop"' \
  && ok "…and a second claimant is told who has it, not handed it again" || no "…and a second claimant is told who has it, not handed it again" "$again"
! body "${CONSOLE[@]}" "$H/console/pending" | grep -q "\"id\":\"$ID\"" && ok "…and it is no longer pending" || no "…and it is no longer pending" "still listed"
done_=$(body -X PUT "${CONSOLE[@]}" -d '{"state":"done","report":"down — only you can see it","by":"studio"}' "$H/console/record/$PAGE/pending/$ID")
echo "$done_" | grep -q '"state":"done"' && echo "$done_" | grep -q '"done_at":"20' && ok "…and marked done with the words the verb said" || no "…and marked done with the words the verb said" "$done_"
body "${CONSOLE[@]}" "$H/console/record/$PAGE/pending" | grep -q "down — only you can see it" && ok "…which the record's queue still shows" || no "…which the record's queue still shows" "gone"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"state":"maybe"}' "$H/console/record/$PAGE/pending/$ID")" = 400 ] && ok "…and a state that is not a state is refused" || no "…and a state that is not a state is refused" "not 400"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"state":"done"}' "$H/console/record/$PAGE/pending/nope")" = 404 ] && ok "…and an item nobody asked for is nothing" || no "…and an item nobody asked for is nothing" "not 404"

# ---- invites: the way somebody gets on a film without him opening Cloudflare -
NEWCOMER="ad@example.com"
IKEY="cccccccccccccccccccccccccccccccc"
IHASH=$(printf '%s' "$IKEY" | shasum -a 256 | cut -d' ' -f1)
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[],"invites":[{"hash":"%s","role":"viewer","expires":null}]}' "$DIRECTOR" "$IHASH")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null

[ "$(code "$H/f/$FILM?as=$NEWCOMER")" = 403 ] && ok "a newcomer cannot open the film yet" || no "a newcomer cannot open the film yet" "not 403"
[ "$(code "$H/f/$FILM/join?i=$IKEY&as=$NEWCOMER")" = 302 ] && ok "taking an invite lets them in" || no "taking an invite lets them in" "not 302"
[ "$(code "$H/f/$FILM?as=$NEWCOMER")" = 200 ] && ok "…and they stay in afterwards" || no "…and they stay in afterwards" "not 200"

got=$(body "$H/f/$FILM/api/people?as=$OWNER")
echo "$got" | grep -q "$NEWCOMER" && ok "he can see who joined, and how" || no "he can see who joined, and how" "not listed"

[ "$(code "$H/f/$FILM/api/people?as=$NEWCOMER")" = 403 ] && ok "somebody who joined is still only a viewer" || no "somebody who joined is still only a viewer" "not 403"
[ "$(code "$H/f/$FILM/join?i=$IKEY&k=$KEY")" = 403 ] && ok "a bearer key cannot take an invite" || no "a bearer key cannot take an invite" "not 403"
[ "$(code "$H/f/$FILM/join?i=dddddddddddddddddddddddddddddddd&as=$NEWCOMER")" = 403 ] && ok "a made-up invite is refused" || no "a made-up invite is refused" "not 403"

sent=$(printf '{"people":[],"links":[],"invites":[{"hash":"%s","role":"viewer","expires":"2020-01-01"}]}' "$IHASH")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
[ "$(code "$H/f/$FILM/join?i=$IKEY&as=late@example.com")" = 403 ] && ok "an invite that ran out is refused" || no "an invite that ran out is refused" "not 403"

sent=$(printf '{"people":[],"links":[],"invites":[]}' )
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
[ "$(code "$H/f/$FILM/join?i=$IKEY&as=late@example.com")" = 403 ] && ok "a cancelled invite is refused" || no "a cancelled invite is refused" "not 403"

# ---- the two halves must agree about what a log is --------------------------
#
# His real film has four iCloud conflict copies called "… 2.log". `state` used
# to offer them and `log/<name>` refused them, and the page died whole.
printf 'shotlister-log 1\n' > /tmp/hubcheck-odd.log
(cd "$HERE" && $W r2 object put "shotlister-preview/p/$FILM/logs/0000000000000001-000000000000000a 2.log" --file /tmp/hubcheck-odd.log --local --persist-to "$STATE" >/dev/null 2>&1)
rm -f /tmp/hubcheck-odd.log
got=$(body "$H/f/$FILM/api/state?as=$OWNER")
echo "$got" | grep -q " 2.log" && no "a log it would refuse is not offered" "offered it" || ok "a log it would refuse is not offered"

# ---- the MCP: the same tools, on an address any AI can reach -----------------
#
# Seeded as a **second film** so nothing above is disturbed, and with real
# change logs rather than a bare header, because the point of this section is
# that the engine replays a film in a worker and can write one back.
#
# **A trap, so nobody chases it twice.** `wrangler dev` rewrites the route's
# hostname to localhost inside response *headers* — so `Location` and
# `WWW-Authenticate` come back saying `mcp.localhost:8788:8788` however right
# the worker was. Response *bodies* are left alone. Everything below therefore
# reads addresses out of bodies and follows redirects by their path.
MFILM="01a02852ebb00198e46a252100000000"
MCPH="mcp.your-domain.example:$PORT"
APEXH="your-domain.example:$PORT"

printf '{"format":1,"project":"%s","title":"Daybreak","engine":"0.1.0"}' "$MFILM" > /tmp/hubcheck-manifest.json
(cd "$HERE" && $W r2 object put "shotlister-preview/p/$MFILM/manifest.json" --file /tmp/hubcheck-manifest.json --local --persist-to "$STATE" >/dev/null 2>&1)
rm -f /tmp/hubcheck-manifest.json
for log in "$ROOT"/studio/fixtures/Daybreak.shotlist/changes/*.log; do
  (cd "$HERE" && $W r2 object put "shotlister-preview/p/$MFILM/logs/$(basename "$log")" --file "$log" --local --persist-to "$STATE" >/dev/null 2>&1)
done
# **A second film, so there is somewhere to go back to.** `MFILM` is the same
# id as `FILM` — Daybreak is written over the two-line film rather than beside
# it — so his shelf held one film and the rail rightly drew no way back to
# the others, and the two checks that look for that arrow failed for weeks
# (Ref 835). This one is never opened; it only makes the count two.
OFILM="01a02852ebb00198e46a252100000002"
printf '{"format":1,"project":"%s","title":"The Other One","engine":"0.1.0"}' "$OFILM" > /tmp/hubcheck-other.json
(cd "$HERE" && $W r2 object put "shotlister-preview/p/$OFILM/manifest.json" --file /tmp/hubcheck-other.json --local --persist-to "$STATE" >/dev/null 2>&1)
rm -f /tmp/hubcheck-other.json

# The MCP answers on a host of its own. Locally that name is carried in a
# header, because wrangler serves every route from one port — see `hostAsked`.
asmcp()  { curl -s -H "x-hub-host: $MCPH" "$@"; }
asapex() { curl -s -H "x-hub-host: $APEXH" "$@"; }
mcode()  { curl -s -o /dev/null -w "%{http_code}" -H "x-hub-host: $MCPH" "$@"; }
# The path of a redirect, so it can be followed back at localhost.
whereto() { python3 -c "
import sys, urllib.parse as u
p = u.urlparse(sys.argv[1]); print(p.path + ('?' + p.query if p.query else ''))" "$1"; }
param() { python3 -c "
import sys, urllib.parse as u
print(u.parse_qs(u.urlparse(sys.argv[1]).query).get(sys.argv[2], [''])[0])" "$1" "$2"; }

got=$(asmcp "$H/health")
echo "$got" | grep -q '"mcp"' && ok "the MCP answers on a host of its own" || no "the MCP answers on a host of its own" "$got"
echo "$got" | grep -q "mcp.your-domain.example" && ok "…and knows the address it hands out" || no "…and knows the address it hands out" "$got"

# The drift check asks `/version` here, on the MCP's host, because the apex
# has Access in front of it — so it has to answer on this host too.
got=$(asmcp "$H/version")
echo "$got" | grep -q '"commit":"checking-commit"' && ok "…and says its version, so drift.sh can ask without signing in" || no "…and says its version, so drift.sh can ask without signing in" "$got"

# And drift.sh itself reads it: pointed at this run rather than the air. The
# stamp is a made-up word, so the honest answer is that no checkout has it.
got=$(DRIFT_HUB_URL="$H/version" "$HERE/drift.sh" hub 2>&1)
echo "$got" | grep -q "checking-commit live" && ok "drift.sh reads the live commit" || no "drift.sh reads the live commit" "$got"

got=$(asmcp "$H/.well-known/oauth-protected-resource")
echo "$got" | grep -q '"authorization_servers"' && ok "it says where to sign in" || no "it says where to sign in" "$got"
got=$(asmcp "$H/.well-known/oauth-authorization-server")
echo "$got" | grep -q '"code_challenge_methods_supported":\["S256"\]' \
  && ok "…and that it wants PKCE" || no "…and that it wants PKCE" "$got"

# **The one rule this endpoint exists to hold.** Nothing is answered without a
# token, and the refusal has to say where to get one or a client is stuck.
[ "$(mcode -X POST "$H/mcp" -d '{"jsonrpc":"2.0","id":1,"method":"initialize"}')" = 401 ] \
  && ok "no token, no answer" || no "no token, no answer" "not 401"
asmcp -D- -o /dev/null -X POST "$H/mcp" -d '{}' | grep -qi "www-authenticate" \
  && ok "…and the refusal says where to sign in" || no "…and the refusal says where to sign in" "no header"
[ "$(mcode -X POST "$H/mcp" -H 'authorization: Bearer not-a-real-token-at-all' -d '{}')" = 401 ] \
  && ok "a made-up token is refused" || no "a made-up token is refused" "not 401"

# ---- signing in, the whole way through --------------------------------------
reg=$(asmcp -X POST "$H/register" -H 'content-type: application/json' \
  -d '{"client_name":"Claude","redirect_uris":["http://localhost:9999/cb"]}')
CLIENT=$(printf '%s' "$reg" | python3 -c "import sys,json;print(json.load(sys.stdin).get('client_id',''))" 2>/dev/null)
[ -n "$CLIENT" ] && ok "an AI can register itself" || no "an AI can register itself" "$reg"

VERIFIER="checking-verifier-checking-verifier-1234567890"
CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\n')
ASKING="response_type=code&client_id=$CLIENT&redirect_uri=http%3A%2F%2Flocalhost%3A9999%2Fcb&state=xyz&code_challenge=$CHALLENGE&code_challenge_method=S256"

# An address the client never registered is exactly the shape of somebody
# arranging for the code to be sent to themselves. Refused, not redirected.
[ "$(mcode "$H/authorize?response_type=code&client_id=$CLIENT&redirect_uri=http%3A%2F%2Fevil.example%2Fcb&state=x&code_challenge=$CHALLENGE&code_challenge_method=S256")" = 400 ] \
  && ok "a redirect the app never registered is refused" || no "a redirect the app never registered is refused" "not 400"

first=$(asmcp -o /dev/null -w "%{redirect_url}" "$H/authorize?$ASKING")
[ -n "$first" ] && ok "signing in sends you to the apex" || no "signing in sends you to the apex" "no redirect"
second=$(asapex -o /dev/null -w "%{redirect_url}" "$H$(whereto "$first")")
GRANT=$(param "$second" grant)
[ -n "$GRANT" ] && ok "the apex signs who you are onto the note" || no "the apex signs who you are onto the note" "no grant"

# A note nobody signed must not be taken, or the address in it is anybody's.
asmcp "$H/authorize?grant=eyJraW5kIjoiZ3JhbnRlZCJ9.bm90YXNpZ25hdHVyZQ" | grep -q "took too long" \
  && ok "an unsigned note is refused" || no "an unsigned note is refused" "took it"

CONSENT=$(asmcp "$H$(whereto "$second")")
echo "$CONSENT" | grep -q "wants to connect to Studio" \
  && ok "you are shown what is asking before it is allowed" || no "you are shown what is asking before it is allowed" "no consent page"
# **The page may change its look and words, never what it posts** (consent
# screen redesign, 2026-10-19): one form, post, the signed note and the answer.
printf '%s' "$CONSENT" | python3 -c "
import sys, re
h = sys.stdin.read()
forms = re.findall(r'<form[^>]*>.*?</form>', h, re.S)
ok = len(forms) == 1 and 'method=\"post\"' in forms[0]
ins = re.findall(r'<input[^>]*>', forms[0]) if forms else []
ok = ok and len(ins) == 1 and 'type=\"hidden\"' in ins[0] and 'name=\"grant\"' in ins[0]
btns = re.findall(r'<button[^>]*name=\"answer\"[^>]*value=\"(\w+)\"', forms[0]) if forms else []
ok = ok and btns == ['yes', 'no'] and len(re.findall(r'<button', forms[0])) == 2
ok = ok and 'name=\"grant\" value=\"' + '$GRANT' + '\"' in h
sys.exit(0 if ok else 1)" \
  && ok "…and the page still posts the signed note and a yes or a no, and nothing else" \
  || no "…and the page still posts the signed note and a yes or a no, and nothing else" "form changed"

backurl=$(asmcp -o /dev/null -w "%{redirect_url}" -X POST "$H/authorize" \
  --data-urlencode "grant=$GRANT" --data-urlencode "answer=yes")
CODE=$(param "$backurl" code)
[ -n "$CODE" ] && ok "allowing hands the app a code" || no "allowing hands the app a code" "$backurl"

# PKCE is the only thing standing between a stolen code and a token.
got=$(asmcp -X POST "$H/token" -d "grant_type=authorization_code" -d "code=$CODE" \
  -d "client_id=$CLIENT" --data-urlencode "code_verifier=wrong-verifier-wrong-verifier-1234")
echo "$got" | grep -q "invalid_grant" && ok "a code without its proof is refused" || no "a code without its proof is refused" "$got"

# …and that refusal must have spent the code, or a guesser gets endless tries.
got=$(asmcp -X POST "$H/token" -d "grant_type=authorization_code" -d "code=$CODE" \
  -d "client_id=$CLIENT" --data-urlencode "code_verifier=$VERIFIER")
echo "$got" | grep -q "invalid_grant" && ok "a code is good once, even when the first try failed" \
  || no "a code is good once, even when the first try failed" "$got"

# Now do it properly, from the top.
first=$(asmcp -o /dev/null -w "%{redirect_url}" "$H/authorize?$ASKING")
second=$(asapex -o /dev/null -w "%{redirect_url}" "$H$(whereto "$first")")
GRANT=$(param "$second" grant)
backurl=$(asmcp -o /dev/null -w "%{redirect_url}" -X POST "$H/authorize" \
  --data-urlencode "grant=$GRANT" --data-urlencode "answer=yes")
CODE=$(param "$backurl" code)
got=$(asmcp -X POST "$H/token" -d "grant_type=authorization_code" -d "code=$CODE" \
  -d "client_id=$CLIENT" --data-urlencode "code_verifier=$VERIFIER")
TOKEN=$(printf '%s' "$got" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
[ -n "$TOKEN" ] && ok "the code becomes a token" || no "the code becomes a token" "$got"

# ---- the tools --------------------------------------------------------------
tell1() { asmcp -X POST "$H/mcp" -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d "$1"; }
# **His yes, for the checks written before the two steps** (2026-10-19): a
# tool that answers a preview and a `confirm` token (Share, What Viewers See,
# view links, Show on Portal, archive / remove a page) is called again with
# that token, as the chat does after his yes. The two steps themselves —
# step 1 writes nothing, a bad / used / foreign token is refused — are
# checked in mcpconsole.mjs.
tell() {
  local got again
  got=$(tell1 "$1")
  again=$(printf '%s' "$1" | GOT="$got" python3 -c '
import json, os, re, sys
ask = json.load(sys.stdin)
p = ask.get("params") or {}
a = p.get("arguments")
if ask.get("method") != "tools/call" or not isinstance(a, dict) or a.get("confirm"): sys.exit(0)
try: text = "".join(c.get("text", "") for c in json.loads(os.environ["GOT"])["result"]["content"])
except Exception: sys.exit(0)
m = re.search(r"\"confirm\": \"(ok-[0-9a-f]{20})\"", text)
if not m or "\"next\": \"Nothing has changed yet" not in text: sys.exit(0)
a["confirm"] = m.group(1)
print(json.dumps(ask))' 2>/dev/null)
  if [ -n "$again" ]; then tell1 "$again"; else printf '%s' "$got"; fi
}
said() { printf '%s' "$1" | python3 -c "
import sys, json
got = json.load(sys.stdin)
if 'error' in got: print('ERROR:', got['error']['message'])
else: print(''.join(c.get('text','') for c in got['result'].get('content', [])))" 2>/dev/null; }

got=$(tell '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
count=$(printf '%s' "$got" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['result']['tools']))" 2>/dev/null)
[ "${count:-0}" -ge 18 ] && ok "the engine's own tools are offered ($count)" || no "the engine's own tools are offered" "$count"
# The two that want a filesystem are taken off rather than left to fail.
printf '%s' "$got" | grep -q '"attach"' && no "a tool that cannot work here is not offered" "attach is listed" \
  || ok "a tool that cannot work here is not offered"
printf '%s' "$got" | grep -q '"projects"' && ok "…and one that only exists here is" || no "…and one that only exists here is" "no projects tool"
printf '%s' "$got" | python3 -c "import sys,json; t=[t for t in json.load(sys.stdin)['result']['tools'] if t['name']=='export']; assert len(t)==1 and 'Google Drive' in t[0]['description'] and 'preset' in t[0]['inputSchema']['properties']" \
  && ok "export is offered once, the portal's: it files in Drive" || no "export is offered once, the portal's" "missing or twice"
printf '%s' "$got" | grep -q '"export_pages"' && no "the engine's export halves are not offered" "export_pages listed" \
  || ok "the engine's export halves are not offered"

got=$(said "$(tell '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"summary"}}')")
printf '%s' "$got" | grep -q "No project is open" && ok "a tool before any film is open says so" || no "a tool before any film is open says so" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"projects"}}')")
printf '%s' "$got" | grep -q "Daybreak" && ok "he is offered his own films" || no "he is offered his own films" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"open_project","arguments":{"film":"Daybreak"}}}')")
printf '%s' "$got" | grep -q '"scenes":4' && ok "a film opens, replayed from its change logs" || no "a film opens, replayed from its change logs" "$got"

# A film remembered under its portal's old id (the connector's open film kept
# Halcyon's after the portal was carried into the film, 2026-10-13) goes to the
# film, and follow_doc answers in words rather than a bare object.
OPENKEY=$(printf '%s' "$CLIENT|$OWNER" | shasum -a 256 | cut -d' ' -f1)
printf '{"project":"%s"}' "$NOFILM" > /tmp/hubcheck-open-old.json
put "mcp/open/$OPENKEY.json" /tmp/hubcheck-open-old.json
got=$(said "$(tell '{"jsonrpc":"2.0","id":901,"method":"tools/call","params":{"name":"summary"}}')")
printf '%s' "$got" | grep -q "Oddity, Filmed" && ok "a film remembered under its portal's old id opens the film it became" || no "a film remembered under its portal's old id opens the film it became" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":902,"method":"tools/call","params":{"name":"follow_doc","arguments":{"slug":"prep","doc":"1abcdefghijklmnopqrstuvwxyz0123456789","on":false}}}')")
printf '%s' "$got" | grep -q "Stopped Following" && ok "follow_doc answers in words" || no "follow_doc answers in words" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"open_project","arguments":{"film":"Daybreak"}}}')")

got=$(said "$(tell '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"scenes"}}')")
printf '%s' "$got" | grep -q "COUNTY JAIL" && ok "…and reads the same as it does on the Mac" || no "…and reads the same as it does on the Mac" "$got"

before=$(body "$H/f/$MFILM/api/state?as=$OWNER" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['logs']))")
got=$(said "$(tell '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"add_shot","arguments":{"scene":"33","description":"Written from an AI, anywhere","size":"WIDE"}}}')")
printf '%s' "$got" | grep -q "Added 33" && ok "an AI can add a shot from anywhere" || no "an AI can add a shot from anywhere" "$got"

# **The whole point, and the only check that proves it.** A worker keeps nothing
# between requests, so a second request seeing the shot means it really went
# into the bucket as a change log and was replayed back out.
got=$(said "$(tell '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"shots","arguments":{"scene":"33"}}}')")
printf '%s' "$got" | grep -q "Written from an AI" && ok "…and a later request sees it" || no "…and a later request sees it" "$got"
after=$(body "$H/f/$MFILM/api/state?as=$OWNER" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['logs']))")
[ "$after" -gt "$before" ] && ok "…because it wrote a change log the relay will carry" || no "…because it wrote a change log the relay will carry" "$before then $after"

# ---- the film is brought up from its saved state, not replayed -------------
# His row, 2026-09-16 (Ref 1021): after a replay the worker keeps the film's
# state in its cache under the logs' names and sizes, and the next request
# puts it back and adds only what grew. The reply says which road it took in
# `x-shotlister-film`; what it says must not depend on the road.
road() { asmcp -D - -o /dev/null -X POST "$H/mcp" -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d "$1" | tr -d '\r' | sed -n 's/^[Xx]-[Ss]hotlister-[Ff]ilm: //p'; }
SHOTS='{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"shots","arguments":{"scene":"33"}}}'
# The `shots` above found the new log and put the film back from the state
# saved before it, adding that one log on top — and saved the state again.
# So this same question is now answered from the saved state alone.
got=$(road "$SHOTS")
[ "$got" = "restored" ] && ok "a second look at an unchanged film is put back from its saved state" || no "a second look at an unchanged film is put back from its saved state" "road: $got"
from_state=$(said "$(tell "$SHOTS")")
printf '%s' "$from_state" | grep -q "Written from an AI" && ok "…and still sees the shot added a request ago" || no "…and still sees the shot added a request ago" "$from_state"

# A change makes the state stale: the next request restores it and takes in
# only the new log, and reads exactly as the whole film would.
got=$(said "$(tell '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"add_shot","arguments":{"scene":"33","description":"A second shot from an AI","size":"CU"}}}')")
printf '%s' "$got" | grep -q "Added 33" || no "a second shot is added for the saved-state check" "$got"
got=$(road "$SHOTS")
[ "$got" = "restored+tail" ] && ok "after a change, the saved state is put back and only the new log added" || no "after a change, the saved state is put back and only the new log added" "road: $got"
tailed=$(said "$(tell "$SHOTS")")
printf '%s' "$tailed" | grep -q "A second shot from an AI" && ok "…and the new shot is there" || no "…and the new shot is there" "$tailed"
printf '%s' "$tailed" | grep -q "Written from an AI" && ok "…beside the one from before" || no "…beside the one from before" "$tailed"

# **The bucket keeps one copy of the film's logs** (2026-10-13), so a
# datacentre whose cache has never seen the film reads one object, not every
# log — the 20-to-43-second share link. It follows the film: after the change
# above it holds the shot that change added.
copied=$(cd "$HERE" && $W r2 object get "shotlister-preview/hub/logs/$MFILM.txt" --pipe --local --persist-to "$STATE" 2>/dev/null)
printf '%s' "$copied" | grep -q "A second shot from an AI" \
  && ok "the bucket keeps a copy of the film's logs, up to its last change" \
  || no "the bucket keeps a copy of the film's logs, up to its last change" "copy: $(printf '%s' "$copied" | head -c 120)"

# ---- Visibility from the connector (2026-10-02, calm pass 2026-10-03) --------
# What Viewers See is a tool pair: anything he can do on the portal, the
# connector can do. `private` and `public` are the words; `hide` and `show`
# still work. For Me is retired and refused.
got=$(said "$(tell '{"jsonrpc":"2.0","id":901,"method":"tools/call","params":{"name":"set_visibility","arguments":{"private":{"sections":["people"]}}}}')")
printf '%s' "$got" | grep -q "made private people" && ok "an AI makes a page private" || no "an AI makes a page private" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":902,"method":"tools/call","params":{"name":"visibility"}}')")
printf '%s' "$got" | python3 -c "import json,sys; v=json.load(sys.stdin); sys.exit(0 if 'people' in v['private']['sections'] and 'for_me' not in v else 1)" 2>/dev/null \
  && ok "…and reads it back as private, with no For Me" || no "…and reads it back as private, with no For Me" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":903,"method":"tools/call","params":{"name":"set_visibility","arguments":{"private":{"sections":["no-such-page"]}}}}')")
printf '%s' "$got" | grep -q "No section called no-such-page" && ok "…and refuses a page the film does not have" || no "…and refuses a page the film does not have" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":904,"method":"tools/call","params":{"name":"set_visibility","arguments":{"show":{"sections":["people"]}}}}')")
printf '%s' "$got" | grep -q "made public people" && ok "…and the older word shows it again" || no "…and the older word shows it again" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":905,"method":"tools/call","params":{"name":"set_visibility","arguments":{"for":"me","hide":{"sections":["people"]}}}}')")
printf '%s' "$got" | grep -qi "For Me is retired" && ok "…and For Me is refused" || no "…and For Me is refused" "$got"

# ---- Who can open the film, from the connector (move 3, 2026-10-03) ----------
# The Share popover's People tab — the list, roles, the general link — is a
# tool pair too: anything he can do in the popover, the connector can do.
got=$(said "$(tell '{"jsonrpc":"2.0","id":911,"method":"tools/call","params":{"name":"access"}}')")
printf '%s' "$got" | python3 -c "import json,sys; v=json.load(sys.stdin); sys.exit(0 if 'general_access' in v and isinstance(v['people'], list) else 1)" 2>/dev/null \
  && ok "an AI reads who can open the film" || no "an AI reads who can open the film" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":912,"method":"tools/call","params":{"name":"set_access","arguments":{"add":[{"email":"mcp.test@example.com","role":"editor"}]}}}')")
printf '%s' "$got" | grep -q "added mcp.test@example.com" && ok "…adds a person" || no "…adds a person" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":913,"method":"tools/call","params":{"name":"access"}}')")
printf '%s' "$got" | grep -q '"mcp.test@example.com"' && ok "…who is then on the list" || no "…who is then on the list" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":914,"method":"tools/call","params":{"name":"set_access","arguments":{"role":[{"email":"mcp.test@example.com","role":"viewer"}],"link":"anyone"}}}')")
printf '%s' "$got" | grep -q "is a viewer" && printf '%s' "$got" | grep -q "anyone with the link" && ok "…changes a role and turns the link on" || no "…changes a role and turns the link on" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":915,"method":"tools/call","params":{"name":"set_access","arguments":{"remove":["mcp.test@example.com"],"link":"restricted"}}}')")
printf '%s' "$got" | grep -q "removed mcp.test@example.com" && ok "…removes them and turns the link off" || no "…removes them and turns the link off" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":916,"method":"tools/call","params":{"name":"set_access","arguments":{"remove":["owner@example.com"]}}}')")
printf '%s' "$got" | grep -q "he cannot be removed" && ok "…and will not remove him" || no "…and will not remove him" "$got"

# ---- a film's master lists, edited as lists (2026-09-30) ---------------------
# His ask: add the lenses off a rental invoice to a film's lens list. Until now
# the only way a list grew was a shot being given a new value — so a thread
# borrowed a shot and set its lens to each new one in turn. The list has its
# own verbs now, and a later request (a fresh worker) has to see what one wrote.
got=$(said "$(tell '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"add_to_list","arguments":{"list":"lens","terms":["75mm","40mm"],"by_number":true}}}')")
printf '%s' "$got" | grep -q "Added to the lens list: 75mm, 40mm" && ok "an AI puts lenses on a film's list, several at once" || no "an AI puts lenses on a film's list, several at once" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"lists","arguments":{"list":"lens"}}}')")
printf '%s' "$got" | grep -q '"term":"40mm"' && printf '%s' "$got" | grep -q '"term":"75mm"' \
  && ok "…and a later request reads them off the list" || no "…and a later request reads them off the list" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"lock_list","arguments":{"list":"lens"}}}')")
got=$(said "$(tell '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"add_to_list","arguments":{"list":"lens","terms":["300mm"]}}}')")
printf '%s' "$got" | grep -q "locked" && ok "…and a locked list says so rather than growing" || no "…and a locked list says so rather than growing" "$got"
tell '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"lock_list","arguments":{"list":"lens","locked":false}}}' >/dev/null

# ---- everything he can do in the app, through the web door (2026-09-30) ------
# His rule: the connector does whatever the app does. A sample of the new
# areas, each written by one request and read back by a later one — which is
# the only proof a stateless worker really kept it.
tell '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"add_scene","arguments":{"number":"90"}}}' >/dev/null
tell '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"add_shot","arguments":{"scene":"90"}}}' >/dev/null
got=$(said "$(tell '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"add_day","arguments":{"date":"2026-10-03","name":"Pickups"}}}')")
printf '%s' "$got" | grep -q "Pickups" && ok "an AI adds a shoot day" || no "an AI adds a shoot day" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"schedule_scene","arguments":{"scenes":["90"],"day":"Pickups"}}}')")
printf '%s' "$got" | grep -q "scenes 90" && ok "…puts a scene on it" || no "…puts a scene on it" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"schedule","arguments":{}}}')")
printf '%s' "$got" | grep -q '"name":"Pickups"' && printf '%s' "$got" | grep -q '"scene":"90"' \
  && ok "…and a later request reads the schedule back" || no "…and a later request reads the schedule back" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"add_location","arguments":{"name":"Checking Yard","address":"1 Main St"}}}')")
got=$(said "$(tell '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"locations","arguments":{}}}')")
printf '%s' "$got" | grep -q '"address":"1 Main St"' && ok "an AI adds a location, read back later" || no "an AI adds a location, read back later" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"save_version","arguments":{"name":"Checked"}}}')")
got=$(said "$(tell '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"versions","arguments":{}}}')")
printf '%s' "$got" | grep -q '"name":"Checked"' && ok "a version saved from a chat is still there next time" || no "a version saved from a chat is still there next time" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"delete_day","arguments":{"day":"Pickups"}}}')")
printf '%s' "$got" | grep -q "Nothing was removed" && ok "…and a day with shots is not removed without asking" || no "…and a day with shots is not removed without asking" "$got"
# Put the film back as the checks after this expect it.
tell '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"delete_day","arguments":{"day":"Pickups","even_with_shots":true}}}' >/dev/null
tell '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"delete_location","arguments":{"location":"Checking Yard"}}}' >/dev/null
tell '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"archive_scene","arguments":{"scene":"90"}}}' >/dev/null
got=$(said "$(tell '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"delete_scene","arguments":{"scene":"90"}}}')")
printf '%s' "$got" | grep -q "Deleted scene 90" || no "the scene made for these checks goes again" "$got"

# ---- a shot marked Shot from the page ----------------------------------------
# His ruling, 2026-09-22: the portal is the on-set reader, so it has to be
# able to say "we got this". `PUT api/mark` goes through the same engine an
# AI's `update_shot` does and lands as a change log; a viewer is refused.
before=$(body "$H/f/$MFILM/api/state?as=$OWNER" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['logs']))")
got=$(body -X PUT -H 'content-type: application/json' -d '{"shot":"33A","done":true}' "$H/f/$MFILM/api/mark?as=$OWNER")
printf '%s' "$got" | grep -q '"ok":true' && ok "an editor marks a shot Shot from the page" || no "an editor marks a shot Shot from the page" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"shots","arguments":{"scene":"33"}}}')")
printf '%s' "$got" | grep -q '"struck":true' && ok "…and the film says so on the next read" || no "…and the film says so on the next read" "$got"
after=$(body "$H/f/$MFILM/api/state?as=$OWNER" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['logs']))")
[ "$after" -gt "$before" ] && ok "…as a change log the relay will carry" || no "…as a change log the relay will carry" "$before then $after"
got=$(body -X PUT -H 'content-type: application/json' -d '{"shot":"33A","done":false}' "$H/f/$MFILM/api/mark?as=$OWNER")
printf '%s' "$got" | grep -q '"ok":true' && ok "…and the mark comes off the same way" || no "…and the mark comes off the same way" "$got"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"shot":"33A","done":true}' "$H/f/$MFILM/api/mark?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot mark a shot" || no "a viewer cannot mark a shot" "not 403"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"shot":"","done":true}' "$H/f/$MFILM/api/mark?as=$OWNER")" = 400 ] \
  && ok "a mark with no shot named is refused" || no "a mark with no shot named is refused" "not 400"


# **Equal to a whole replay, not merely plausible.** The film is opened in
# a fresh engine in this shell — every log fetched and replayed, no saved
# state anywhere — and its answer to the same question must match the
# worker's word for word.
whole=$(cd "$HERE" && node --input-type=module -e '
import { readFileSync } from "node:fs";
const wasm = await WebAssembly.instantiate(readFileSync("src/mcp.wasm"), {});
const x = wasm.instance.exports;
const put = (t) => { const b = new TextEncoder().encode(t); const p = x.alloc(b.length); new Uint8Array(x.memory.buffer, p, b.length).set(b); return [p, b.length]; };
const take = (p) => { const n = new DataView(x.memory.buffer).getUint32(p, true); const t = new TextDecoder().decode(new Uint8Array(x.memory.buffer, p + 4, n)); x.free_result(p); return t; };
x.set_now(Date.now()); x.set_seed(1);
const [ip, il] = put(process.argv[1]); const [tp, tl] = put("Daybreak"); const [dp, dl] = put("0000000000000001");
x.start(ip, il, tp, tl, 1, dp, dl);
const H = process.argv[2], film = process.argv[1], who = process.argv[3];
const state = await (await fetch(`${H}/f/${film}/api/state?as=${who}`)).json();
for (const log of state.logs.sort((a, b) => a.name < b.name ? -1 : 1)) {
  const text = await (await fetch(`${H}/f/${film}/api/log/${log.name}?as=${who}`)).text();
  const [p, n] = put(text); x.add_log(p, n); x.dealloc(p, n);
}
x.settle();
const [mp, ml] = put(process.argv[4]);
const reply = JSON.parse(take(x.handle(mp, ml)));
process.stdout.write(reply.result.content.map((c) => c.text).join("\n"));
' "$MFILM" "$H" "$OWNER" "$SHOTS" 2>/dev/null)
[ -n "$whole" ] && [ "$whole" = "$tailed" ] && ok "…and reads word for word as the whole film replayed" || no "…and reads word for word as the whole film replayed" "differs: $(printf '%s' "$whole" | head -c 200)"

# A tool that needs a Mac says so in one line rather than half working.
got=$(said "$(tell '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"attach","arguments":{"path":"/tmp/x.png","scene":"33"}}}')")
printf '%s' "$got" | grep -q "no files" && ok "a tool that needs a Mac says so" || no "a tool that needs a Mac says so" "$got"

# ---- the portal's front of house, written by the MCP ------------------------
#
# The rule these hold is the one the whole card rests on: **the words come from
# the caller and the film's own facts do not.** A count or a ratio that arrived
# as an argument is a number somebody transcribed, and it would go quietly wrong
# the first time a scene was added.
got=$(said "$(tell '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"set_front","arguments":{"logline":"A wife follows a trail of petals.","status":"Active","shoot_start":"2026-11-02","shoot_end":"2026-11-04","documents":[{"name":"Look Book","kind":"lookbook","url":"https://drive.google.com/lookbook"},{"name":"Nowhere at all"},{"name":"Nasty","url":"javascript:alert(1)"}],"crew":[{"name":"Ellis Ward","role":"Gaffer","department":"G&E","email":"ellis@example.com","phone":"+1 555 0100"}]}}}')")
echo "$got" | grep -q "your-domain.example" && ok "set_front writes a film's page" || no "set_front writes a film's page" "$got"
echo "$got" | grep -q "2 documents dropped" && ok "a document with no link and no file is dropped, and says so" || no "a document with no link and no file is dropped, and says so" "$got"
# `javascript:` is not a far-fetched thing to guard against here: the card is
# written by an agent reading somebody else's page.
echo "$got" | grep -qv "javascript" && ok "a javascript: address never reaches the card" || no "a javascript: address never reaches the card" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"front"}}')")
echo "$got" | grep -q "trail of petals" && ok "front reads back what was written" || no "front reads back what was written" "$got"
# Counts are the film's, not the caller's — Daybreak's real fixture has scenes.
printf '%s' "$got" | python3 -c "
import sys, json
got = json.loads(sys.stdin.read())
sys.exit(0 if got['counts']['scenes'] > 0 and got['ratio'] > 0 else 1)" \
  && ok "the counts and the ratio are asked of the film" || no "the counts and the ratio are asked of the film" "$got"

# ---- the film half of the card is the film's, live ---------------------------
# His row, 2026-09-16: the page must never be behind the film. A stored card
# claiming ninety-nine scenes and a director nobody cast is read back with what
# the replayed film says — so Update the Portal is for the words only.
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-front-live.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-front-live.json'))
f['counts']['scenes'] = 99
f['director'] = 'Nobody Cast'
f['days'] = [{'label': 'Day 9', 'date': '2031-01-01'}]
f['pictures']['scenes'] = ['ffffffffffffffffffffffffffffffff.png']
json.dump(f, open('/tmp/hubcheck-front-live.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-front-live.json
rm -f /tmp/hubcheck-front-live.json
got=$(body "$H/f/$MFILM/api/front?as=$OWNER")
printf '%s' "$got" | python3 -c "
import sys, json
got = json.loads(sys.stdin.read())
sys.exit(0 if 0 < got['counts']['scenes'] < 99 else 1)" \
  && ok "the card's counts come from the film, not from what was stored" || no "the card's counts come from the film, not from what was stored" "$got"
echo "$got" | grep -q "Nobody Cast" \
  && no "…and so do the credits" "the stored director was drawn" || ok "…and so do the credits"
echo "$got" | grep -q "2031-01-01" \
  && no "…and the days" "a stored day was drawn" || ok "…and the days"
echo "$got" | grep -q "ffffffffffffffffffffffffffffffff" \
  && no "…and the pictures" "a stored picture was drawn" || ok "…and the pictures"
echo "$got" | grep -q "trail of petals" \
  && ok "…while the words stay what Notion or the MCP wrote" || no "…while the words stay what Notion or the MCP wrote" "$got"

# ---- a file put on the page, and served back --------------------------------
got=$(said "$(tell '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"A note","filename":"note.txt","base64":"aGVsbG8gZnJvbSB0aGUgcG9ydGFs"}}}')")
FILE=$(printf '%s' "$got" | sed -n 's/.*as \([0-9a-f]*\.[a-z]*\)\..*/\1/p')
[ -n "$FILE" ] && ok "add_document stores a file by its own contents" || no "add_document stores a file by its own contents" "$got"
[ "$(body "$H/f/$MFILM/pic/$FILE?as=$OWNER")" = "hello from the portal" ] \
  && ok "the file it stored is served back" || no "the file it stored is served back" "not the bytes"
[ "$(code "$H/f/$MFILM/pic/$FILE?as=$STRANGER")" = 403 ] \
  && ok "a stranger cannot read a film's documents" || no "a stranger cannot read a film's documents" "not 403"
# **And by its name.** `/file/a-note.txt` is the address the page writes now
# (2026-09-19); the content address stays for every page already served.
[ "$(body "$H/f/$MFILM/file/a-note.txt?as=$OWNER")" = "hello from the portal" ] \
  && ok "the same file answers under its own name" || no "the same file answers under its own name" "$(code "$H/f/$MFILM/file/a-note.txt?as=$OWNER")"
body "$H/f/$MFILM/documents?as=$OWNER" | grep -q "/file/a-note.txt" \
  && ok "…and that is the address on the Documents page" || no "…and that is the address on the Documents page" "the page still links the hash"
[ "$(code "$H/f/$MFILM/file/nothing-here.txt?as=$OWNER")" = 404 ] \
  && ok "a name nothing answers to is nothing" || no "a name nothing answers to is nothing" "not 404"

# **A document is saved under a name a person can read.** His note,
# 2026-09-07: the Download button handed him `29cb989a….pdf`, because a file is
# stored by its own contents. The film and the document's name make the one a
# browser saves it under; a still is left alone, since nobody saves those by
# hand and the header would be paid for on every tile of a mood board.
disp=$(curl -s -D - -o /dev/null "$H/f/$MFILM/pic/$FILE?as=$OWNER" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Dd]isposition: //p')
# The day it was filed goes on the end (see `datedName`), so this matches the
# stem and the extension rather than the whole name — which is what made this
# check red from the day the date landed until 2026-09-08.
case "$disp" in
  *A-note*.txt*) ok "a document is saved under a legible name" ;;
  *) no "a document is saved under a legible name" "said \"$disp\"" ;;
esac
case "$disp" in
  *"$FILE"*) no "…and not under its own hash" "said \"$disp\"" ;;
  *) ok "…and not under its own hash" ;;
esac

# **The apps' own naming system** (Ref 1570): Film_Document_YYYY-MM-DD.ext —
# fields by underscores, words by hyphens, the date last — exactly what the Mac
# and the phone call an export, so a file saved from here sorts with theirs.
printf '%s' "$disp" | grep -Eq 'filename="Daybreak_A-note_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"' \
  && ok "…as Film_Document_Date, the apps' own system" || no "…as Film_Document_Date, the apps' own system" "said \"$disp\""
got=$(said "$(tell '{"jsonrpc":"2.0","id":2201,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"Let'"'"'s Look: Book #2","filename":"second.txt","base64":"c2Vjb25kIG5vdGU="}}}')")
FILE2=$(printf '%s' "$got" | sed -n 's/.*as \([0-9a-f]*\.[a-z]*\)\..*/\1/p')
disp2=$(curl -s -D - -o /dev/null "$H/f/$MFILM/pic/$FILE2?as=$OWNER" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Dd]isposition: //p')
printf '%s' "$disp2" | grep -Eq 'filename="Daybreak_Lets-Look-Book-2_[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"' \
  && ok "…apostrophes dropped, punctuation one hyphen, no spaces" || no "…apostrophes dropped, punctuation one hyphen, no spaces" "said \"$disp2\""

# **A Download button downloads, and a Documents card still opens.**
#
# His report, 2026-09-08: *"the download PDF on Safari iOS just links to another
# page where the PDF opens instead of downloading."* Measured in the Simulator
# on iPhone 17 Pro rather than reasoned about, and it took two findings:
# Safari on iOS ignores the `download` attribute entirely, and it renders a PDF
# in its own viewer even when told `attachment` — a `.zip` with the identical
# header raises its download prompt, so the machinery works and the type is the
# only lever. So the link says which it wants with `?save=1`, and a file being
# saved goes out as bytes.
head=$(curl -s -D - -o /dev/null "$H/f/$MFILM/pic/$FILE?save=1&as=$OWNER" | tr -d '\r')
case "$head" in
  *[Cc]ontent-[Dd]isposition:*attachment*) ok "a Download button asks to be saved, not opened" ;;
  *) no "a Download button asks to be saved, not opened" "no attachment" ;;
esac
case "$head" in
  *[Cc]ontent-[Tt]ype:*application/octet-stream*) ok "…and goes out as bytes, so a phone cannot preview it" ;;
  *) no "…and goes out as bytes, so a phone cannot preview it" "still typed" ;;
esac
case "$head" in
  *A-note*.txt*) ok "…still under a name a person can read" ;;
  *) no "…still under a name a person can read" "lost its name" ;;
esac
case "$disp" in
  *inline*) ok "a document opened from the film still opens" ;;
  *) no "a document opened from the film still opens" "said \"$disp\"" ;;
esac

got=$(said "$(tell '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"Bad","filename":"x.exe","base64":"aGk="}}}')")
echo "$got" | grep -qi "cannot put" && ok "a file it will not serve is refused outright" || no "a file it will not serve is refused outright" "$got"

# ---- and the pages a person actually opens ----------------------------------
got=$(body "$H/f/$MFILM?as=$OWNER")
echo "$got" | grep -q "trail of petals" && ok "the film's page carries its logline" || no "the film's page carries its logline" "no logline"
# **The door is gone and that is the design.** His approval, 2026-09-04: the way
# into the program is the rail, on every page, with no crossing. What has to
# be true is that the film's page leads to the shot list, among the rest.
echo "$got" | grep -q 'href="[^"]*/shotlist"' && echo "$got" | grep -q "Shot List" \
  && ok "the rail leads into the program" || no "the rail leads into the program" "no way in"
body "$H/f/$MFILM/add?as=$OWNER" | grep -q '/bible"' && body "$H/f/$MFILM/add?as=$OWNER" | grep -q '/camera"' \
  && ok "and the record's pages are named on Add, filled or not" || no "and the record's pages are named on Add, filled or not" "no list"
echo "$got" | grep -q "2 &#8211; 4 November\|2 – 4 November" \
  && ok "shoot dates read as dates, not as ISO" || no "shoot dates read as dates, not as ISO" "$(echo "$got" | grep -o 'Shoot.\{0,80\}' | head -1)"

got=$(body "$H/f/$MFILM/crew?as=$OWNER")
echo "$got" | grep -q "mailto:ellis@example.com" && ok "a crew address is a link you can tap" || no "a crew address is a link you can tap" "no mailto"
echo "$got" | grep -q "tel:+15550100" && ok "a crew number is a link you can call" || no "a crew number is a link you can call" "no tel"
echo "$got" | grep -q "G&amp;E" && ok "the crew is grouped by department" || no "the crew is grouped by department" "no department"

# **Contacts are an editor's to see, not a link holder's.** This route never
# called mustEdit, so anybody with an unlisted link could reach it by typing the
# path and read every crew member's address and telephone number — and nothing
# on the share window said a link included that.
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[]}' "$DIRECTOR")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$MFILM/api/people?as=$OWNER" >/dev/null
got=$(body "$H/f/$MFILM/crew?as=$DIRECTOR")
echo "$got" | grep -q "Ellis Ward" \
  && ok "a viewer still sees who is on the film" || no "a viewer still sees who is on the film" "no name"
echo "$got" | grep -q "Gaffer" \
  && ok "and what they do" || no "and what they do" "no role"
echo "$got" | grep -q "mailto:ellis@example.com" \
  && no "a viewer is not given a crew address" "the mailto is there" || ok "a viewer is not given a crew address"
echo "$got" | grep -q "tel:+15550100" \
  && no "a viewer is not given a crew number" "the tel is there" || ok "a viewer is not given a crew number"
echo "$got" | grep -q "ellis@example.com" \
  && no "the address is not on the page at all, link or no link" "it is in the text" || ok "the address is not on the page at all, link or no link"

got=$(body "$H/f/$MFILM/documents?as=$OWNER")
echo "$got" | grep -q "Look Book" && ok "the documents page lists what was pinned" || no "the documents page lists what was pinned" "no look book"
echo "$got" | grep -q 'rel="noopener noreferrer"' && ok "a link out of the card is opened safely" || no "a link out of the card is opened safely" "no rel"

got=$(body "$H/?as=$OWNER")
echo "$got" | grep -q "Active" && ok "the shelf shows a film's status" || no "the shelf shows a film's status" "no status"

# ---- the camera spec sheet --------------------------------------------------
#
# It is absent until he has one, and that is the point: a spec sheet with blank
# rows on it is worse than no spec sheet, so the whole block stays off the page
# rather than drawing empty labels.
# ---- who sees what ----------------------------------------------------------
#
# **The one rule this file exists for, applied to the newest thing that can
# break it.** A hidden section, a hidden crew member and a hidden document must
# be refused *by the server*: not missing from a rail while the address still
# answers, and not absent from a page while the bytes still serve. Everything
# below therefore asks as the person who should not have it.
seevis() {
  printf '%s' "$1" > /tmp/hubcheck-visible.json
  (cd "$HERE" && $W r2 object put "shotlister-preview/p/$MFILM/visible.json" \
    --file /tmp/hubcheck-visible.json --local --persist-to "$STATE" >/dev/null 2>&1)
  rm -f /tmp/hubcheck-visible.json
}

[ "$(code "$H/f/$MFILM/visibility?as=$OWNER")" = 200 ] \
  && ok "an administrator can say what is shown" || no "an administrator can say what is shown" "not 200"
[ "$(code "$H/f/$MFILM/visibility?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot" || no "a viewer cannot" "not 403"
[ "$(code "$H/f/$MFILM/visibility?as=$STRANGER")" = 403 ] \
  && ok "and neither can a stranger" || no "and neither can a stranger" "not 403"

seevis '{"version":1,"sections":["camera"],"crew":["Ellis Ward"],"documents":["A note"]}'

[ "$(code "$H/f/$MFILM/camera?as=$DIRECTOR")" = 404 ] \
  && ok "a hidden section does not answer at its own address" || no "a hidden section does not answer at its own address" "not 404"
echo "$(body "$H/f/$MFILM?as=$DIRECTOR")" | grep -q "/camera" \
  && no "and it is gone from the rail" "the row is still there" || ok "and it is gone from the rail"
[ "$(code "$H/f/$MFILM/camera?as=$OWNER")" = 200 ] \
  && ok "…while he still sees it himself" || no "…while he still sees it himself" "not 200"

echo "$(body "$H/f/$MFILM/crew?as=$DIRECTOR")" | grep -q "Ellis Ward" \
  && no "a hidden crew member is not on the page at all" "the name is in the text" || ok "a hidden crew member is not on the page at all"
echo "$(body "$H/f/$MFILM/crew?as=$OWNER")" | grep -q "Ellis Ward" \
  && ok "…and he still is, to him" || no "…and he still is, to him" "the name is gone for him too"

echo "$(body "$H/f/$MFILM/documents?as=$DIRECTOR")" | grep -q "A note" \
  && no "a hidden document is not listed" "it is listed" || ok "a hidden document is not listed"
[ "$(code "$H/f/$MFILM/pic/$FILE?as=$DIRECTOR")" = 404 ] \
  && ok "…and its bytes are refused, not merely unlisted" || no "…and its bytes are refused, not merely unlisted" "the file still serves"
[ "$(body "$H/f/$MFILM/pic/$FILE?as=$OWNER")" = "hello from the portal" ] \
  && ok "…while he can still open it" || no "…while he can still open it" "not the bytes"

# **Hiding the shot list shuts the program's own address too**, not just the row.
seevis '{"version":1,"sections":["shotlist"],"crew":[],"documents":[]}'
[ "$(code "$H/f/$MFILM/shotlist?as=$DIRECTOR")" = 404 ] \
  && ok "a hidden part of the program is shut as well" || no "a hidden part of the program is shut as well" "not 404"
[ "$(code "$H/f/$MFILM/shotlist?as=$OWNER")" = 200 ] \
  && ok "…and open to him" || no "…and open to him" "not 200"

# **And the program's own rail hides what the record's rail hides.** His
# report, 2026-09-10: "when you click into one of the Shotlister Studio based
# pages … every tab on the sidebar, even the ones that I've hidden from the
# public link, become exposed." The app draws its rail in the browser from
# what the page hands it, so the hidden keys have to travel with the page and
# the names of hidden pages must not.
seevis '{"version":1,"sections":["locations","people","camera"],"crew":[],"documents":[]}'
got=$(body "$H/f/$MFILM/shotlist?as=$DIRECTOR")
# Visibility's list comes first; anything empty follows it (`unfilled`).
echo "$got" | grep -q '"hidden":\["locations","people","camera"' \
  && ok "the program is told what a viewer may not see" \
  || no "the program is told what a viewer may not see" "no hidden list"
echo "$got" | grep -q '"crew":0' \
  && ok "…and not how many people are behind a hidden page" \
  || no "…and not how many people are behind a hidden page" "the count is in the page"
echo "$(body "$H/f/$MFILM/shotlist?as=$OWNER")" | grep -q '"hidden":\[\]' \
  && ok "…while he is hidden nothing" || no "…while he is hidden nothing" "hidden for him too"
grep -q 'filter((r) => !hidden(r.at)' "$HERE/public/film.js" \
  && grep -q 'if (hidden(b.dataset.mode)) return;' "$HERE/public/film.js" \
  && ok "…and the app's rail leaves them out, and refuses the switch" \
  || no "…and the app's rail leaves them out, and refuses the switch" "film.js does not read it"

# Put it back, so nothing below inherits a hidden film.
seevis '{"version":1,"sections":[],"crew":[],"documents":[]}'
[ "$(code "$H/f/$MFILM/camera?as=$DIRECTOR")" = 200 ] \
  && ok "nothing hidden, and everything is back" || no "nothing hidden, and everything is back" "not 200"

# ---- For Me is retired (his ruling, 2026-10-03) -----------------------------
#
# A page hidden For Me becomes unpinned the first time the film is read, and
# leaves `visible.me`. People and documents hidden For Me are kept in the
# store and applied nowhere: nothing offers the control any more.
seevis '{"version":1,"sections":[],"crew":[],"documents":[],"me":{"sections":["people"],"crew":["Ellis Ward"],"documents":["A note"]}}'
body "$H/f/$MFILM?as=$OWNER" | grep -q 'data-key="people"' \
  && no "a page hidden For Me becomes unpinned" "the row is still there" || ok "a page hidden For Me becomes unpinned"
body "${CONSOLE[@]}" "$H/console/$MFILM/visible" | python3 -c "import json,sys; v=json.load(sys.stdin)['me']; sys.exit(0 if v['sections'] == [] and v['crew'] == ['Ellis Ward'] and v['documents'] == ['A note'] else 1)" \
  && ok "…it left visible.me once, and the people and documents kept" || no "…it left visible.me once, and the people and documents kept" "not migrated"
body "$H/f/$MFILM?as=$OWNER" >/dev/null
body "${CONSOLE[@]}" "$H/console/$MFILM/visible" | python3 -c "import json,sys; v=json.load(sys.stdin)['me']; sys.exit(0 if v['sections'] == [] and v['crew'] == ['Ellis Ward'] else 1)" \
  && ok "…and reading again changes nothing" || no "…and reading again changes nothing" "changed"
[ "$(code "$H/f/$MFILM/crew?as=$OWNER")" = 200 ] \
  && ok "…it still opens at its address, in the Library" || no "…it still opens at its address" "not 200"
body "$H/f/$MFILM/crew?as=$OWNER" | grep -q "Ellis Ward" \
  && ok "a person once hidden For Me is on his People page again" || no "a person once hidden For Me is on his People page again" "still hidden"
# (2026-10-11: the Library no longer pins; what is on the sidebar is the
# sidebar's Add Pages list, `library?part=pick`.)
body "$H/f/$MFILM/library?part=pick&as=$OWNER" | grep -q '"at":"people"[^}]*"on":false' \
  && ok "…and People stands in the Library, unpinned" || no "…and People stands in the Library, unpinned" "not unpinned"
body "$H/f/$MFILM/visibility?part=1&as=$OWNER" | grep -q 'me-sections\|value="me"\|For Me' \
  && no "Visibility offers no For Me" "still there" || ok "Visibility offers no For Me"
[ "$(code -X PUT "${CONSOLE[@]}" -d '{"me":{"crew":["Ellis Ward"]}}' "$H/console/$MFILM/visible")" = 200 ] \
  && [ "$(code -X PUT "${CONSOLE[@]}" -d '{"me":["Ellis Ward"]}' "$H/console/$MFILM/visible")" = 400 ] \
  && ok "the console's door still keeps his old lists, one kind at a time" || no "the console's door still keeps his old lists" "refused"
# Put People back on the sidebar, so nothing below inherits an unpinned film.
body -X POST "$H/f/$MFILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["people"],"action":"pin"}' >/dev/null
seevis '{"version":1,"sections":[],"crew":[],"documents":[]}'

got=$(body "$H/f/$MFILM/camera?as=$OWNER")
echo "$got" | grep -q "No Spec Sheet" && ok "the camera page says so until there is a spec sheet" || no "the camera page says so until there is a spec sheet" "drew one"

got=$(said "$(tell '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"set_front","arguments":{"camera":{"body":"Alexa 35","lenses":"Tribe7 Blackwings T-Tuned","format":"4.6K 16:9","colour":"AWG4/LogC4","codec":"ProRes 4444","fps":"24","capture":"4096 x 2304"}}}}')")
echo "$got" | grep -q "camera spec sheet" && ok "set_front takes a spec sheet" || no "set_front takes a spec sheet" "$got"

# **The spec sheet has a page of its own now**, rather than a block at the foot
# of the film's page — his ruling, 2026-09-02: individual pages, data rich.
got=$(body "$H/f/$MFILM/camera?as=$OWNER")
echo "$got" | grep -q "Alexa 35" && echo "$got" | grep -q "Capture Resolution" \
  && ok "the spec sheet has its own page" || no "the spec sheet has its own page" "not drawn"
echo "$got" | grep -q "Tribe7 Blackwings" \
  && ok "the lens list is kept whole" || no "the lens list is kept whole" "no lenses"

# **The notes and the files, which used to stay in Notion.** His point,
# 2026-09-04: he uploads small files onto a spec sheet and writes notes on it,
# and none of it left Notion. `refresh.py` carries an upload across and leaves a
# Drive link a link; here the page has to draw both, a table in the notes has to
# stay a table, and hiding the sheet has to take its file down with it.
LUT="0102030405060708090a0b0c0d0e0f10.cube"
cat > /tmp/hubcheck-camnotes.json <<'JSON'
[{"t":"h2","r":[{"s":"Prep Notes"}]},
 {"t":"li","r":[{"s":"A-CAM handheld, B-CAM on the Eye Direct"}]},
 {"t":"table","head":true,"k":[{"t":"trow","c":[[{"s":"Dimension"}],[{"s":"Pixels"}]]},
                               {"t":"trow","c":[[{"s":"Horizontal"}],[{"s":"8640"}]]}]}]
JSON
put "p/$MFILM/pages/camera-sheet.json" /tmp/hubcheck-camnotes.json
printf 'a lut, near enough' > /tmp/hubcheck-lut.cube
put "p/$MFILM/media/$LUT" /tmp/hubcheck-lut.cube
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-front.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-front.json'))
f['camera_files'] = [{'name': 'Show LUT', 'file': '$LUT', 'bytes': 18},
                     {'name': 'Production LUT', 'url': 'https://drive.google.com/file/d/abc/view'}]
f['camera_notes'] = 3
json.dump(f, open('/tmp/hubcheck-front.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-front.json
rm -f /tmp/hubcheck-camnotes.json /tmp/hubcheck-lut.cube /tmp/hubcheck-front.json

got=$(body "$H/f/$MFILM/camera?as=$OWNER")
echo "$got" | grep -q "Prep Notes" \
  && ok "the notes on a spec sheet come across" || no "the notes on a spec sheet come across" "not drawn"
echo "$got" | grep -q "8640" \
  && ok "…and a table in them stays a table" || no "…and a table in them stays a table" "no table"
echo "$got" | grep -q "Show LUT" \
  && ok "a file he uploaded is on the page" || no "a file he uploaded is on the page" "not listed"
echo "$got" | grep -q "drive.google.com" \
  && ok "…and a Drive link is left as a link" || no "…and a Drive link is left as a link" "no link"
[ "$(code "$H/f/$MFILM/pic/$LUT?as=$OWNER")" = 200 ] \
  && ok "…and the file itself opens" || no "…and the file itself opens" "not 200"
[ "$(code "$H/f/$MFILM/file/show-lut.cube?as=$OWNER")" = 200 ] \
  && ok "…under its own name as well" || no "…under its own name as well" "not 200"
# Several cameras and labelled LUTs (2026-10-05, src/entries.js): a fact
# with a line per camera is a list, a value they share is said once, and a
# LUT carries the label "LUT Labels" gives it (a link by its address).
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-front0.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-front0.json'))
f['camera'].update(body='A Cam: Alexa 35\nB Cam: FX3', colour='A Cam: AWG4/LogC4\nFX3: S-Gamut3.Cine/S-Log3', codec='ProRes 4444',
  lenses='A Cam: Tribe7 Blackwings — T1.9\nB Cam: Sony G Master — 24-70', luts='Night: https://drive.google.com/file/d/abc/view')
json.dump(f, open('/tmp/hubcheck-front.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-front.json
got=$(body "$H/f/$MFILM/camera?as=$OWNER")
# A column per camera since 2026-10-07: the Camera row names them (as pills,
# each body's label under it, since 111c7659), and every other row's columns
# line up under it — FX3's colour in B Cam's column.
echo "$got" | grep -q '<span class="npcam"><span class="np np-default">Alexa 35</span><i>A Cam</i></span><span class="npcam"><span class="np np-default">FX3</span><i>B Cam</i></span>' \
  && echo "$got" | grep -q '<li><b>AWG4/LogC4</b></li><li><b>S-Gamut3.Cine/S-Log3</b></li>' \
  && ok "several cameras: a line each, matched by label or name" || no "several cameras: a line each, matched by label or name" "$(echo "$got" | grep -o 'camcols.\{0,200\}' | head -3)"
echo "$got" | grep -q '<dd><span class="nps"><span class="np np-default">ProRes 4444</span></span>' && ok "…and a value they share is said once" || no "…and a value they share is said once" "split"
# the LUTs row since 2026-10-14 (specpage.mjs): a label naming no camera sits beside its file
echo "$got" | grep -q '<span class="lut"><i>Night</i>' && ok "a LUT carries its label" || no "a LUT carries its label" "no label"
put "p/$MFILM/front.json" /tmp/hubcheck-front0.json
rm -f /tmp/hubcheck-front.json /tmp/hubcheck-front0.json

seevis '{"version":1,"sections":["camera"],"crew":[],"documents":[]}'
[ "$(code "$H/f/$MFILM/pic/$LUT?as=$DIRECTOR")" = 404 ] \
  && ok "hiding the sheet takes its file down too" || no "hiding the sheet takes its file down too" "the file still serves"
seevis '{"version":1,"sections":[],"crew":[],"documents":[]}'


# ---- the tab, and the pasted link -------------------------------------------
# His ask, 2026-09-04: a film's own icon in the tab, and a cover when a link is
# pasted somewhere. Both come off the mark its Notion row already carries, so
# what is checked here is that the film's own colour and title reach the places
# a person actually sees them — a browser tab, and a card in a message.
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-front2.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-front2.json'))
f['mark'] = {'path': 'M3 3h14v14H3Z', 'colour': '#C2554D'}
# **The logline is left exactly as it was.** Setting one here overwrote the
# line a later check reads back to prove a viewer may still read the film —
# so this check broke that one, three hundred lines away, and the failure
# read as a permission fault. Add the mark; touch nothing else.
json.dump(f, open('/tmp/hubcheck-front2.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-front2.json
# The cover is drawn by `hub/cover.mjs`, which needs a browser; what the hub is
# answerable for is serving it, so a stand-in stands in.
printf 'PNG enough for a check' > /tmp/hubcheck-cover.png
put "p/$MFILM/media/cover.png" /tmp/hubcheck-cover.png
rm -f /tmp/hubcheck-front2.json /tmp/hubcheck-cover.png

got=$(body "$H/f/$MFILM?as=$OWNER")
echo "$got" | grep -q 'rel="icon" type="image/svg+xml"' \
  && ok "the tab carries the film's own mark" || no "the tab carries the film's own mark" "no icon"
[ "$(code "$H/f/$MFILM/icon.svg?as=$OWNER")" = 200 ] \
  && ok "…and that mark is served as a file" || no "…and that mark is served as a file" "not 200"
body "$H/f/$MFILM/icon.svg?as=$OWNER" | grep -q "C2554D" \
  && ok "…in the film's own colour" || no "…in the film's own colour" "wrong colour"
echo "$got" | grep -q 'property="og:title"' \
  && ok "a pasted link says which film it is" || no "a pasted link says which film it is" "no og:title"
echo "$got" | grep -q 'property="og:image"' \
  && ok "…and offers a cover with it" || no "…and offers a cover with it" "no og:image"
[ "$(code "$H/f/$MFILM/cover.png?as=$OWNER")" = 200 ] \
  && ok "…and the cover itself is served" || no "…and the cover itself is served" "not 200"
# A record page is its own thing to be sent, so its card names the page too.
body "$H/f/$MFILM/people?as=$OWNER" | grep -q 'og:title" content="People' \
  && ok "a link to one page names that page" || no "a link to one page names that page" "names only the film"
# 2026-10-01: the program's tabs and Share unfurled as bare addresses. Every
# page a person may be sent carries a card — these were the ones that did not.
body "$H/f/$MFILM/locations?as=$OWNER" | grep -q 'og:title" content="Locations · ' \
  && ok "a link to a program tab names that tab" || no "a link to a program tab names that tab" "no card"
body "$H/f/$MFILM/shotlist?as=$OWNER" | grep -q 'og:image" content="[^"]*cover.png?page=shotlist' \
  && ok "…with that tab's own picture" || no "…with that tab's own picture" "no og:image"
body "$H/f/$MFILM/share?as=$OWNER" | grep -q 'property="og:title"' \
  && ok "even the Share page unfurls" || no "even the Share page unfurls" "no og:title"
# His ask, 2026-09-10: the picture names the page as well. A page's link asks
# for the page's own card; one nobody has drawn yet falls back to the film's,
# and one that has been drawn is the one served.
body "$H/f/$MFILM/people?as=$OWNER" | grep -q 'og:image" content="[^"]*cover.png?page=people' \
  && ok "…and asks for that page's own picture" || no "…and asks for that page's own picture" "asks for the film's"
[ "$(body "$H/f/$MFILM/cover.png?page=people&as=$OWNER")" = "PNG enough for a check" ] \
  && ok "…which is the film's until one is drawn" || no "…which is the film's until one is drawn" "not the film's cover"
printf 'the people card' > /tmp/hubcheck-cover-people.png
put "p/$MFILM/media/cover-people.png" /tmp/hubcheck-cover-people.png
rm -f /tmp/hubcheck-cover-people.png
[ "$(body "$H/f/$MFILM/cover.png?page=people&as=$OWNER")" = "the people card" ] \
  && ok "…and its own once drawn" || no "…and its own once drawn" "still the film's"
[ "$(body "$H/f/$MFILM/cover.png?page=../people&as=$OWNER")" = "PNG enough for a check" ] \
  && ok "…and a made-up page name gets the film's" || no "…and a made-up page name gets the film's" "answered something else"

# ---- the home screen ----------------------------------------------------------
# His ask, 2026-09-20: the portal added to an iPhone's home screen is one app.
# That takes a manifest whose scope is the whole host (a page outside the
# scope is what iOS opens in the browser-with-an-X), a PNG icon (iOS and
# Safari draw no SVG), and the apple meta on every page. `?k=` travels with
# the manifest and the icon so they can be fetched on the share host.
echo "$got" | grep -q 'rel="manifest" href="/f/'"$MFILM"'/manifest.webmanifest" crossorigin="use-credentials"' \
  && ok "a film's page names its own manifest, fetched with credentials" \
  || no "a film's page names its own manifest, fetched with credentials" "no manifest link"
echo "$got" | grep -q 'rel="apple-touch-icon" href="/f/'"$MFILM"'/icon.png"' \
  && ok "…and a PNG for the home screen" || no "…and a PNG for the home screen" "no apple-touch-icon"
echo "$got" | grep -q 'rel="icon" type="image/png" href="/f/'"$MFILM"'/icon.png"' \
  && ok "…and the same PNG for Safari's tab" || no "…and the same PNG for Safari's tab" "no png favicon"
echo "$got" | grep -q 'name="apple-mobile-web-app-capable" content="yes"' \
  && ok "…and asks to run without browser bars" || no "…and asks to run without browser bars" "no apple-mobile-web-app-capable"
echo "$got" | grep -q 'name="apple-mobile-web-app-title" content="Daybreak"' \
  && ok "…under the film's own name" || no "…under the film's own name" "wrong title"
man=$(body "$H/f/$MFILM/manifest.webmanifest?as=$OWNER")
echo "$man" | grep -q '"scope":"/"' \
  && ok "the manifest's scope is the whole host" || no "the manifest's scope is the whole host" "$man"
echo "$man" | grep -q '"display":"standalone"' \
  && ok "…and it stands alone" || no "…and it stands alone" "not standalone"
echo "$man" | grep -q '"name":"Daybreak"' \
  && ok "…named for the film" || no "…named for the film" "wrong name"
echo "$man" | grep -q '"start_url":"/f/'"$MFILM"'"' \
  && ok "…and opens on the film's page" || no "…and opens on the film's page" "wrong start"
[ "$(header "$H/f/$MFILM/manifest.webmanifest?as=$OWNER" content-type)" = "application/manifest+json; charset=utf-8" ] \
  && ok "…served as a manifest" || no "…served as a manifest" "wrong type"
# A key on the address travels into the manifest and the icon it names — on
# the share host, where a key is the only way in. The film's people are put
# back as the crew check above left them.
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[{"hash":"%s","key":"%s","role":"viewer","off":false,"expires":null,"note":"for the producer"}],"invites":[]}' "$DIRECTOR" "$HASH" "$KEY")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$MFILM/api/people?as=$OWNER" >/dev/null
body "${SHARE[@]}" "$H/f/$MFILM?k=$KEY" | grep -q 'rel="manifest" href="/f/'"$MFILM"'/manifest.webmanifest?k='"$KEY"'"' \
  && ok "a page opened by a link names a manifest carrying the key" \
  || no "a page opened by a link names a manifest carrying the key" "no keyed manifest link"
man=$(body "${SHARE[@]}" "$H/f/$MFILM/manifest.webmanifest?k=$KEY")
echo "$man" | grep -q '"start_url":"/f/'"$MFILM"'?k='"$KEY"'"' \
  && ok "…and that manifest opens on the keyed address" || no "…and that manifest opens on the keyed address" "$man"
echo "$man" | grep -q '"src":"/f/'"$MFILM"'/icon.png?k='"$KEY"'"' \
  && ok "…with the key on its icon too" || no "…with the key on its icon too" "$man"
[ "$(code "${SHARE[@]}" "$H/f/$MFILM/icon.png?k=$KEY")" = 200 ] \
  && ok "…and the icon opens with it" || no "…and the icon opens with it" "not 200"
[ "$(code "${SHARE[@]}" "$H/f/$MFILM/manifest.webmanifest")" = 404 ] \
  && ok "…and without a key, on the share host, there is nothing" || no "…and without a key, on the share host, there is nothing" "not 404"
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[]}' "$DIRECTOR")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$MFILM/api/people?as=$OWNER" >/dev/null
# The PNG is drawn by a refresh; until one has run, the product's own mark
# stands in — a picture, never a hole.
[ "$(code "$H/f/$MFILM/icon.png?as=$OWNER")" = 200 ] \
  && ok "a film with no drawn icon still gets one" || no "a film with no drawn icon still gets one" "not 200"
[ "$(body "$H/f/$MFILM/icon.png?as=$OWNER" | head -c 4 | od -An -c | tr -d ' ')" = "211PNG" ] \
  && ok "…and it is a PNG" || no "…and it is a PNG" "not a png"
printf 'the film icon' > /tmp/hubcheck-icon.png
put "p/$MFILM/media/icon.png" /tmp/hubcheck-icon.png
rm -f /tmp/hubcheck-icon.png
[ "$(body "$H/f/$MFILM/icon.png?as=$OWNER")" = "the film icon" ] \
  && ok "…and its own once drawn" || no "…and its own once drawn" "still the product's"
# The shelf — nobody's film — has the hub's own.
shelf=$(body "$H/?as=$OWNER")
echo "$shelf" | grep -q 'rel="manifest" href="/manifest.webmanifest"' \
  && ok "the shelf names the hub's own manifest" || no "the shelf names the hub's own manifest" "no manifest link"
body "$H/manifest.webmanifest?as=$OWNER" | grep -q '"name":"Project Studio".*"scope":"/"' \
  && ok "…named for the shelf, not any one film" || no "…named for the shelf, not any one film" "wrong manifest"
[ "$(code "$H/hub-icon.png")" = 200 ] \
  && ok "…with the shelf's own icon served beside it" || no "…with the shelf's own icon served beside it" "not 200"

# ---- the rail at home, and the way in to Who Sees What ----------------------
# **The name stays in the rail at home** — his report, 2026-09-04, that the top
# of it felt oddly empty. It has to be `data-stowed`: two elements sharing one
# `view-transition-name` abort the transition outright, and the travelling
# title is the move he asked to keep. A check for the name alone would pass
# while the animation was dead, so both halves are asserted.
got=$(body "$H/f/$MFILM?as=$OWNER")
echo "$got" | grep -q 'class="fh-who" data-stowed' \
  && ok "the rail still names the film at home" || no "the rail still names the film at home" "no name"
body "$H/f/$MFILM/people?as=$OWNER" | grep -q 'class="fh-who" data-stowed' \
  && no "…and gives up the travelling name only there" "stowed away from home" \
  || ok "…and gives up the travelling name only there"
# **The panel had no link anywhere at all** — the only way in was to know the
# address. His report, same day: he expected it behind his own initials.
# **Retired 2026-10-11**: what a viewer sees is set in the Library (each row's
# one switch, and Crew), so his initials no longer lead to a second screen.
echo "$got" | grep -q 'class="mego"[^>]*visibility' \
  && no "his initials no longer lead to a second What Viewers See" "still there" \
  || ok "his initials no longer lead to a second What Viewers See"
body "$H/f/$MFILM?as=$DIRECTOR" | grep -q 'class="mego"' \
  && no "…and nobody else is shown it" "a viewer was offered it" \
  || ok "…and nobody else is shown it"
# **What he is, inside the menu rather than beside the circle** — his
# instruction, 2026-09-04. Administrator is a second thing he is, not a bigger
# Editor, so both are said.
echo "$got" | grep -q 'class="memay">Editor · Administrator<' \
  && ok "the menu says what he is" || no "the menu says what he is" "not said"
echo "$got" | grep -q '<span class="me">' \
  && no "…and the rail's foot no longer does" "still beside the circle" \
  || ok "…and the rail's foot no longer does"


# ---- the four modes are four addresses --------------------------------------
got=$(body "$H/f/$MFILM/locations?as=$OWNER")
echo "$got" | grep -q '"mode":"locations"' && ok "a tile opens the app in the mode it names" || no "a tile opens the app in the mode it names" "no mode"
[ "$(code "$H/f/$MFILM/nonsense?as=$OWNER")" = 404 ] && ok "a mode nobody has is not a page" || no "a mode nobody has is not a page" "not 404"

# ---- a viewer is refused here too, by the server ----------------------------
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[],"invites":[]}' "$DIRECTOR")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$MFILM/api/people?as=$OWNER" >/dev/null
dreg=$(asmcp -X POST "$H/register" -H 'content-type: application/json' \
  -d '{"client_name":"Claude","redirect_uris":["http://localhost:9999/cb"]}')
DCLIENT=$(printf '%s' "$dreg" | python3 -c "import sys,json;print(json.load(sys.stdin).get('client_id',''))" 2>/dev/null)
DASK="response_type=code&client_id=$DCLIENT&redirect_uri=http%3A%2F%2Flocalhost%3A9999%2Fcb&state=x&code_challenge=$CHALLENGE&code_challenge_method=S256"
first=$(asmcp -o /dev/null -w "%{redirect_url}" "$H/authorize?$DASK")
second=$(curl -s -H "x-hub-host: $APEXH" -o /dev/null -w "%{redirect_url}" "$H$(whereto "$first")&as=$DIRECTOR")
DGRANT=$(param "$second" grant)
backurl=$(asmcp -o /dev/null -w "%{redirect_url}" -X POST "$H/authorize" \
  --data-urlencode "grant=$DGRANT" --data-urlencode "answer=yes")
DCODE=$(param "$backurl" code)
DTOKEN=$(asmcp -X POST "$H/token" -d "grant_type=authorization_code" -d "code=$DCODE" \
  -d "client_id=$DCLIENT" --data-urlencode "code_verifier=$VERIFIER" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
dtell() { asmcp -X POST "$H/mcp" -H "authorization: Bearer $DTOKEN" -H 'content-type: application/json' -d "$1"; }
got=$(said "$(dtell '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"open_project","arguments":{"film":"Daybreak"}}}')")
printf '%s' "$got" | grep -q '"read_only":true' && ok "a viewer's AI is told the film is read only" || no "a viewer's AI is told the film is read only" "$got"
got=$(said "$(dtell '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"set_front","arguments":{"logline":"Not yours to write."}}}')")
echo "$got" | grep -qi "only an editor" && ok "a viewer cannot rewrite the film's page" || no "a viewer cannot rewrite the film's page" "$got"
got=$(body "$H/f/$MFILM/api/front?as=$DIRECTOR")
echo "$got" | grep -q "trail of petals" && ok "but a viewer may read it" || no "but a viewer may read it" "$got"

# ---- the logline goes through the project record (2026-10-05, the Notion link)
# Written onto the card alone, a logline the AI set was put back from Notion by
# the next refresh. Now `set_front` writes the record (a version, the history,
# and the Studio's link carries it into Notion), and any write to the record's
# logline shows on the film's page at once.
# (Bodies built with printf into a variable first: bash 3.2 brace-expands an
# escaped-quote JSON inside "$( … )".)
set_front() { local rpc; rpc=$(printf '{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"set_front","arguments":%s}}' "$1"); said "$(tell "$rpc")"; }
nowv() { body "${CONSOLE[@]}" "$F" | python3 -c "import sys,json;print(json.load(sys.stdin)['facts'].get('$1',{}).get('v',0))"; }
v=$(nowv logline)
put_body=$(printf '{"changes":{"logline":{"value":"A logline typed in Notion.","base":%s}},"by":"notion"}' "$v")
[ "$(code -X PUT "${CONSOLE[@]}" -d "$put_body" "$F")" = 200 ] \
  && body "$H/f/$MFILM?as=$OWNER" | grep -q "A logline typed in Notion." \
  && ok "a logline written to the record shows on the film's page at once" || no "a logline written to the record shows on the film's page at once" "$(body "$H/f/$MFILM/api/front?as=$OWNER" | head -c 300)"
set_front "$(printf '{"source":"notion:%s"}' "$PAGE")" >/dev/null
got=$(set_front '{"logline":"Written by the AI connector.","synopsis":"Two days, one kitchen."}')
facts=$(body "${CONSOLE[@]}" "$F")
echo "$got" | grep -q "went into the project record" \
  && echo "$facts" | grep -q '"value":"Written by the AI connector.","v":'"$((v+2))" \
  && echo "$facts" | grep -q '"by":"portal AI connector"' && echo "$facts" | grep -q 'Two days, one kitchen.' \
  && ok "set_front writes the logline and synopsis into the record" || no "set_front writes the logline and synopsis into the record" "$got / $facts"
body "$H/f/$MFILM?as=$OWNER" | grep -q "Written by the AI connector." \
  && ok "…and the film's page shows it" || no "…and the film's page shows it" "not on the page"
body "${CONSOLE[@]}" "$H/console/record/$PAGE/history" | grep -q '"to":"Written by the AI connector."' \
  && ok "…and it is in the record's history" || no "…and it is in the record's history" "not in history"
# The director's note and the visual language go the same way (2026-10-05):
# a note written to the record shows on the film's page at once, as one line,
# and set_front's `note` and `look` land in the record by its names.
v=$(nowv directors_note)
put_body=$(printf '{"changes":{"directors_note":{"value":"A note typed in Notion.\\n\\nIts second paragraph.","base":%s}},"by":"notion"}' "$v")
[ "$(code -X PUT "${CONSOLE[@]}" -d "$put_body" "$F")" = 200 ] \
  && body "$H/f/$MFILM?as=$OWNER" | grep -q "A note typed in Notion. Its second paragraph." \
  && ok "a director's note written to the record shows on the film's page at once" || no "a director's note written to the record shows on the film's page at once" "$(body "$H/f/$MFILM/api/front?as=$OWNER" | head -c 300)"
got=$(set_front '{"note":"Written as a note.","look":"Written as a look."}')
facts=$(body "${CONSOLE[@]}" "$F")
echo "$facts" | python3 -c "import sys,json; f=json.load(sys.stdin)['facts']; assert f['directors_note']['value']=='Written as a note.' and f['visual_language']['value']=='Written as a look.'" \
  && ok "set_front writes the note and the look into the record" || no "set_front writes the note and the look into the record" "$got / $facts"
before=$(nowv logline)
set_front '{"logline":"Written by the AI connector."}' >/dev/null
[ "$(nowv logline)" = "$before" ] && ok "…the same words again write nothing" || no "…the same words again write nothing" "version moved"
got=$(said "$(dtell '{"jsonrpc":"2.0","id":41,"method":"tools/call","params":{"name":"set_front","arguments":{"logline":"Not yours either."}}}')")
echo "$got" | grep -qi "only an editor" && ! body "${CONSOLE[@]}" "$F" | grep -q "Not yours either" \
  && ok "…and a viewer's AI still cannot" || no "…and a viewer's AI still cannot" "$got"
# ---- the AI connector reaches the whole record (2026-10-05, branch mcp-record)
# Projects Console's record grew past the four facts set_front wrote: status,
# type, length, client, agency, colour, icon, shoot dates, website, Drive
# folder, credits as lists, custom links, and what a project hides. Every one
# the connector writes goes through the record (a version, the history, by
# the AI connector), and a fact the project hides is refused, never wiped.
# (Arguments built by python into a variable: bash 3.2 and nested quotes.)
use() { local rpc; rpc=$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':50,'method':'tools/call','params':{'name':sys.argv[1],'arguments':json.loads(sys.argv[2])}}))" "$1" "$2"); said "$(tell "$rpc")"; }
fact() { body "${CONSOLE[@]}" "$F" | python3 -c "import sys,json; f=json.load(sys.stdin)['facts'].get('$1') or {}; v=f.get('value'); print(v if isinstance(v,str) else json.dumps(v))" 2>/dev/null; }
factby() { body "${CONSOLE[@]}" "$F" | python3 -c "import sys,json; print((json.load(sys.stdin)['facts'].get('$1') or {}).get('by',''))" 2>/dev/null; }
readout() { body -X PUT "${CONSOLE[@]}" -d "$(printf '{"version":1,"page":"%s","name":"Call Her Back","slug":"call-her-back","stage":"Active","director":"Clara Moreau","lights":{"drive":"on","film":"on"},"film":{"title":"Call Her Back","relay":"%s"},"hidden":%s}' "$PAGE" "$FILM" "$1")" "$H/console/record/$PAGE" >/dev/null; }
list=$(tell '{"jsonrpc":"2.0","id":51,"method":"tools/list"}')
printf '%s' "$list" | python3 -c "import sys,json; n={t['name'] for t in json.load(sys.stdin)['result']['tools']}; assert {'record','set_record','set_credit','add_record_link','remove_record_link','set_front','update_project','summary'} <= n" \
  && ok "the connector offers the record's tools" || no "the connector offers the record's tools" "missing"
got=$(use record '{}')
printf '%s' "$got" | python3 -c "import sys,json; r=json.load(sys.stdin); assert r['facts']['logline']['value']=='Written by the AI connector.' and r['facts']['logline']['v']>0 and r['hidden']==[] and 'credits' in r and 'links' in r" \
  && ok "record reads the project's facts, each with its version" || no "record reads the project's facts, each with its version" "$got"
got=$(use set_record '{"client":"Acme Express","agency":"Fabrica","color":"Orange","icon":"dining","website":"https://example.com/lets-bake","shoot_dates":"2026-10-06 / 2026-10-07","status":"development"}')
[ "$(fact client)" = "Acme Express" ] && [ "$(fact color)" = orange ] && [ "$(fact icon)" = "https://www.notion.so/icons/dining_orange.svg" ] \
  && [ "$(fact shoot_dates)" = "2026-10-06/2026-10-07" ] && [ "$(fact status)" = Development ] \
  && [ "$(factby agency)" = "portal AI connector" ] \
  && ok "set_record writes client, agency, colour, icon, website, dates and status into the record" || no "set_record writes client, agency, colour, icon, website, dates and status into the record" "$got"
body "$H/f/$MFILM/api/front?as=$OWNER" | grep -q '"status":"Development"' \
  && ok "…and a status written to the record shows on the film's page at once" || no "…and a status written to the record shows on the film's page at once" "$(body "$H/f/$MFILM/api/front?as=$OWNER" | head -c 300)"
before=$(nowv status)
got=$(use set_record '{"status":"Post"}')
echo "$got" | grep -q "set_stage" && [ "$(nowv status)" = "$before" ] \
  && ok "…a Post status asks him first (set_stage), not set_record" || no "…a Post status asks him first (set_stage), not set_record" "$got"
got=$(use set_record '{"shoot_dates":"2026-10-07/2026-10-06","website":"not an address"}')
echo "$got" | grep -q "Nothing written" && echo "$got" | grep -q "before the first" && [ "$(fact website)" = "https://example.com/lets-bake" ] \
  && ok "…a backwards date or a bad address is refused, and nothing is written" || no "…a backwards date or a bad address is refused, and nothing is written" "$got"
got=$(use set_record '{"type":"Space Opera"}')
echo "$got" | grep -q "choices in use" && ok "…a type Notion has no choice for is refused" || no "…a type Notion has no choice for is refused" "$got"
got=$(use set_record "$(printf '{"agency":"Somebody else","seen":{"agency":%s}}' "$(( $(nowv agency) - 1 ))")")
echo "$got" | grep -q "changed since it was read" && [ "$(fact agency)" = Fabrica ] \
  && ok "…a write from a version that has moved on is refused" || no "…a write from a version that has moved on is refused" "$got"
got=$(use set_credit '{"role":"producer","people":["Marta Delgado","Max Kowalski"]}')
[ "$(fact producer)" = "Marta Delgado & Max Kowalski" ] \
  && fact credits | python3 -c "import sys,json; c=json.load(sys.stdin); assert {'role':'Producer','people':['Marta Delgado','Max Kowalski']} in c" \
  && ok "set_credit writes the list and the credit's line together" || no "set_credit writes the list and the credit's line together" "$got / $(fact credits)"
use set_credit '{"role":"Line Producer","people":["Marta Delgado"]}' >/dev/null
[ "$(fact line_producer)" = "Marta Delgado" ] && ok "…a Line Producer too" || no "…a Line Producer too" "$(fact line_producer)"
got=$(use set_credit '{"role":"Gaffer","people":["Ellis Ward"]}')
echo "$got" | grep -q "A credit is one of" && ok "…and only a credit the record knows" || no "…and only a credit the record knows" "$got"
# people-unified (2026-10-05): every credit is its own Projects property in
# Notion, so every credit has its line fact beside the list — a company too.
use set_credit '{"role":"Production Company","people":["Hum Studio"]}' >/dev/null
[ "$(fact production_company)" = "Hum Studio" ] \
  && fact credits | python3 -c "import sys,json; c=json.load(sys.stdin); assert {'role':'Production Company','people':['Hum Studio']} in c" \
  && ok "…and every credit's line, a Production Company too" || no "…and every credit's line, a Production Company too" "$(fact production_company) / $(fact credits)"
use set_credit '{"role":"Production Company","people":[]}' >/dev/null
[ "$(fact production_company)" = "" ] && ok "…and [] takes it off, line and all" || no "…and [] takes it off, line and all" "$(fact production_company)"
# Shoot names and lens sets (2026-10-05): `record` says each shoot's own
# name (an older copy without `name` read from its title) and its spec
# sheet's lens sets; `front` says the lens sets beside the Lenses text.
putfact() { local b; b=$(python3 -c "import json,sys; print(json.dumps({'changes':{sys.argv[1]:{'value':json.loads(sys.argv[2]),'base':int(sys.argv[3])}},'by':'console'}))" "$1" "$2" "$(nowv "$1")"); code -X PUT "${CONSOLE[@]}" -d "$b" "$F"; }
cam0=$(use front '{}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('camera') or {}))")
lens2=$(python3 -c "import json,sys; c=json.loads(sys.argv[1]); c['lenses']='A Cam: Angenieux Optimo — 45-165mm — T2.3\nB Cam: Signature Primes — 18, 25, 35mm — T1.8 — from Odd Kinds'; print(json.dumps({'camera':c}))" "$cam0")
set_front "$lens2" >/dev/null
putfact shoot_name '"Malibu Pickup"' >/dev/null
use record '{}' | python3 -c "
import sys,json; r=json.load(sys.stdin)
assert r['shoots']==[] and r['shoot_name']['value']=='Malibu Pickup' and r['shoot_name']['v']>0, r.get('shoot_name')
s=r['lens_sets']; assert [x['label'] for x in s]==['A Cam','B Cam'] and s[1]['focals']==['18','25','35mm'] and s[1]['stop']=='T1.8' and s[1]['notes']=='from Odd Kinds', s" \
  && ok "record says the project's own shoot's name and lens sets" || no "record says the project's own shoot's name and lens sets" "$(use record '{}' | head -c 600)"
use front '{}' | python3 -c "
import sys,json; c=json.load(sys.stdin)['camera']
assert c['lenses'].count(chr(10))==1 and [x['series'] for x in c['lens_sets']]==['Angenieux Optimo','Signature Primes'] and c['lens_sets'][0]['focals']==['45-165mm']" \
  && ok "front says the lens sets beside the Lenses text" || no "front says the lens sets beside the Lenses text" "$(use front '{}' | head -c 600)"
rows='[{"id":"1111111111111111111111111111aaaa","title":"Call Her Back — Shoot 1","label":"Shoot 1","n":1,"start":"2026-07-09","end":"","status":"Wrapped"},{"id":"2222222222222222222222222222bbbb","title":"Call Her Back — Shoot 2 · Malibu Pickup","label":"Shoot 2 · Malibu Pickup","n":2,"start":"2026-10-06","end":"","status":"Upcoming"},{"id":"3333333333333333333333333333cccc","title":"Call Her Back — Shoot 3 · Night Exteriors","label":"Shoot 3 · Night Exteriors","name":"Night Exteriors","n":3,"start":"2026-11-01","end":"","status":"Upcoming"}]'
putfact shoots "$rows" >/dev/null
use record '{}' | python3 -c "
import sys,json; r=json.load(sys.stdin)
assert [s['name'] for s in r['shoots']]==['','Malibu Pickup','Night Exteriors'], r['shoots']
assert 'lens_sets' not in r" \
  && ok "…and each Shoots row's own name, from its title when the copy predates it" || no "…and each Shoots row's own name, from its title when the copy predates it" "$(use record '{}' | head -c 600)"
putfact shoots '[]' >/dev/null; putfact shoot_name '""' >/dev/null
set_front "$(python3 -c "import json,sys; print(json.dumps({'camera':json.loads(sys.argv[1])}))" "$cam0")" >/dev/null
got=$(use add_record_link '{"slot":"deck","url":"https://docs.google.com/presentation/d/abc/edit","title":"Treatment"}')
id=$(printf '%s' "$got" | sed -n 's/.*(id \([0-9a-f]*\)).*/\1/p')
fact links | grep -q '"title": "Treatment"' && [ -n "$id" ] && ok "add_record_link keeps a custom link on the record" || no "add_record_link keeps a custom link on the record" "$got"
use remove_record_link "$(printf '{"id":"%s"}' "$id")" >/dev/null
fact links | grep -q Treatment && no "…and remove_record_link takes it off" "still there" || ok "…and remove_record_link takes it off"
# update_project's names go to the record; summary reads them from there.
orig=$(use summary '{}' | python3 -c "import sys,json; print(json.load(sys.stdin)['director'])")
got=$(use update_project '{"director":"Ivy Sterling & Robin Vale Arden"}')
echo "$got" | grep -q "project record" && [ "$(fact director)" = "Ivy Sterling & Robin Vale Arden" ] \
  && fact credits | python3 -c "import sys,json; c=json.load(sys.stdin); assert {'role':'Director','people':['Ivy Sterling','Robin Vale Arden']} in c" \
  && ok "update_project's director goes into the record, one person each" || no "update_project's director goes into the record, one person each" "$got"
use summary '{}' | python3 -c "import sys,json; s=json.load(sys.stdin); assert s['director']=='Ivy Sterling & Robin Vale Arden' and s['client']=='Acme Express' and s['hidden']==[]" \
  && ok "…and summary reads the names from the record" || no "…and summary reads the names from the record" "$(use summary '{}' | head -c 400)"
# The credits the connector writes follow the console's credits.py: a line
# newer than the list wins for its credit, names are tidied and deduplicated,
# and the plan writes the list and each line that moved, from their versions.
# (Expected values computed with credits.py, 2026-10-05.)
node --input-type=module - "$HERE" <<'JS' && ok "the connector's credits follow the console's rules" || no "the connector's credits follow the console's rules" "credits.js and credits.py disagree"
const { creditsOf, creditsPlan, withPeople } = await import(process.argv[2] + "/src/credits.js");
const facts = { credits: { value: [{ role: "Producer", people: ["A"] }, { role: "Director", people: ["Ivy Sterling"] }], v: 3, at: "2026-10-05T10:00:00Z" },
  director: { value: "Ivy Sterling & Robin Vale Arden", v: 4, at: "2026-10-05T11:00:00Z" },
  producer: { value: "A", v: 2, at: "2026-10-05T09:00:00Z" } };
const of = creditsOf(facts);
const want = JSON.stringify([{ role: "Director", people: ["Ivy Sterling & Robin Vale Arden"] }, { role: "Producer", people: ["A"] }]);
if (JSON.stringify(of) !== want) throw new Error(JSON.stringify(of));
const next = withPeople(of, "Executive Producer", ["Owen Fairweather", "  Tess  Marlow ", "owen fairweather"]);
const plan = creditsPlan(facts, next);
if (JSON.stringify(plan) !== JSON.stringify({ credits: { value: [...JSON.parse(want), { role: "Executive Producer", people: ["Owen Fairweather", "Tess Marlow"] }], base: 3 },
  executive_producer: { value: "Owen Fairweather & Tess Marlow", base: 0 } })) throw new Error(JSON.stringify(plan));// people-unified: every credit's line, Writer and Production Company too.
const w = creditsOf({ credits: { value: [{ role: "Writer", people: ["A"] }], v: 1, at: "2026-10-05T10:00:00Z" },
  writer: { value: "B", v: 2, at: "2026-10-05T11:00:00Z" } });
if (JSON.stringify(w) !== JSON.stringify([{ role: "Writer", people: ["B"] }])) throw new Error(JSON.stringify(w));
const pc = creditsPlan({}, [{ role: "Production Company", people: ["Hum Studio"] }]);
if (JSON.stringify(pc) !== JSON.stringify({ credits: { value: [{ role: "Production Company", people: ["Hum Studio"] }], base: 0 },
  production_company: { value: "Hum Studio", base: 0 } })) throw new Error(JSON.stringify(pc));
JS
# What a project hides is refused, and its words are kept.
readout '["logline","client","credit:Writer"]'
got=$(use set_record '{"logline":"A logline on a project that hides it."}')
echo "$got" | grep -q "hidden on this project" && [ "$(fact logline)" = "Written by the AI connector." ] \
  && ok "a fact the project hides is refused, and its words kept" || no "a fact the project hides is refused, and its words kept" "$got"
got=$(set_front '{"logline":"Not on this project.","type":"Narrative"}')
echo "$got" | grep -q "Not kept: Logline" && [ "$(fact logline)" = "Written by the AI connector." ] && [ "$(fact type)" = Narrative ] \
  && ! body "$H/f/$MFILM/api/front?as=$OWNER" | grep -q "Not on this project" \
  && ok "…set_front leaves a hidden logline off and writes the rest" || no "…set_front leaves a hidden logline off and writes the rest" "$got"
got=$(use set_credit '{"role":"Writer","people":["Somebody"]}')
echo "$got" | grep -q "hidden" && ok "…a hidden credit is refused" || no "…a hidden credit is refused" "$got"
got=$(use update_project '{"client":"Someone New"}')
echo "$got" | grep -q "hidden" && [ "$(fact client)" = "Acme Express" ] && ok "…and so is update_project's hidden client" || no "…and so is update_project's hidden client" "$got"
use summary '{}' | python3 -c "import sys,json; s=json.load(sys.stdin); assert s['client']=='' and 'client' in s['hidden']" \
  && ok "…and summary leaves it off, as the film does" || no "…and summary leaves it off, as the film does" "$(use summary '{}' | head -c 400)"
readout '[]'
got=$(said "$(dtell '{"jsonrpc":"2.0","id":52,"method":"tools/call","params":{"name":"set_record","arguments":{"agency":"A viewer"}}}')")
echo "$got" | grep -qi "only an editor" && [ "$(fact agency)" = Fabrica ] && ok "…and a viewer's AI may not change the record" || no "…and a viewer's AI may not change the record" "$got"
use update_project "$(python3 -c "import json,sys; print(json.dumps({'director': sys.argv[1]}))" "$orig")" >/dev/null
use set_record '{"status":"Active"}' >/dev/null
set_front '{"logline":"A wife follows a trail of petals.","source":""}' >/dev/null
got=$(said "$(dtell '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"add_shot","arguments":{"scene":"33","description":"should not happen"}}}')")
printf '%s' "$got" | grep -qi "not change\|reading only" && ok "…and its write is refused by the server" || no "…and its write is refused by the server" "$got"
got=$(said "$(dtell '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"projects"}}')")
printf '%s' "$got" | grep -q "read and change" && no "a viewer is not told they may change" "said they may" || ok "a viewer is not told they may change"

# ---- the studio's lens library and sensor modes, from the connector ---------
# (spec sheet phase 2, kittools.js LIBRARY_TOOLS). One each for every project;
# read by anyone, changed by him; a look writes nothing. Deeper checks live in
# hub/lenslibrary.mjs.
use lens_library '{}' | python3 -c "import sys,json; r=json.load(sys.stdin); assert r['counts']=={'sets':7,'lenses':20,'whole':6} and r['sets'][0]['name']=='ARRI Master Primes' and len(r['sets'][0]['lenses'])==12" \
  && ok "the connector reads the lens library, seeded from the sheets" || no "the connector reads the lens library" "$(use lens_library '{}' | head -c 300)"
got=$(use set_lens_library '{"ops":[{"op":"add","name":"Cooke S4/i 32mm","focal":"32","stop":"T2"}],"look":true}')
echo "$got" | grep -q '"written": false' && use lens_library '{}' | grep -q '"seeded"' \
  && ok "…a look at a change writes nothing" || no "…a look at a change writes nothing" "$got"
got=$(said "$(dtell '{"jsonrpc":"2.0","id":53,"method":"tools/call","params":{"name":"set_lens_library","arguments":{"ops":[{"op":"remove","id":"Laowa Probe2"}],"base":0}}}')")
echo "$got" | grep -qi "only he" && ok "…and only he changes it" || no "…and only he changes it" "$got"
use sensor_modes '{}' | python3 -c "import sys,json; r=json.load(sys.stdin); assert len(r['modes'])==8 and len(r['needing_size'])==7 and r['modes'][0]['width']==36.7" \
  && ok "the connector reads the sensor modes, seven needing a size" || no "the connector reads the sensor modes" "$(use sensor_modes '{}' | head -c 300)"

# ---- a film has a name, and it is an address --------------------------------
#
# His instruction: `your-domain.example/callherback/shotlist`. The film's id
# still works — it is what every link written before this says — and the name
# only resolves for somebody who may open that film, so guessing tells a
# stranger nothing.
#
# **The film is called Daybreak by here.** This battery reuses one id and
# renames it partway through, which is exactly the sort of thing a check that
# hardcodes a title trips over — this one did.
got=$(body "$H/daybreak?as=$OWNER")
echo "$got" | grep -q "Daybreak" && ok "a film answers to its name" || no "a film answers to its name" "not found"
[ "$(code "$H/f/$FILM?as=$OWNER")" = 200 ] && ok "and still to its id" || no "and still to its id" "not 200"

got=$(body "$H/daybreak/shotlist?as=$OWNER")
echo "$got" | grep -q '"mode":"shots"' && ok "and its shot list reads out loud" || no "and its shot list reads out loud" "no mode"
echo "$got" | grep -q '"base":"/daybreak"' \
  && ok "and the page knows the name it was reached by" || no "and the page knows the name it was reached by" "no base"

[ "$(code "$H/daybreak?as=$STRANGER")" = 404 ] \
  && ok "a name a stranger may not open is simply not there" || no "a name a stranger may not open is simply not there" "not 404"
[ "$(code "$H/nosuchfilm?as=$OWNER")" = 404 ] && ok "and a name nobody has is not a page" || no "and a name nobody has is not a page" "not 404"
# The hub's own addresses can never be eaten by a film called Health.
[ "$(code "$H/health")" = 200 ] && ok "the hub's own addresses still win" || no "the hub's own addresses still win" "not 200"

got=$(body "$H/daybreak?as=$OWNER")
echo "$got" | grep -q 'href="/daybreak/shotlist"' \
  && ok "and every link it draws uses the name" || no "and every link it draws uses the name" "still ids"

# ---- the share window -------------------------------------------------------
#
# His instruction, 2026-09-01: it should feel like the window he already knows.
# What these hold is the part that is not decoration — that an editor gets it,
# that nobody else does, and that **the address can be copied again**, which is
# the decision that changed underneath it.
# **What the server sends, not what the window looks like.** The card is drawn
# in the browser — it has to be, because a link's key is made there — so curl
# sees the root and the script and nothing else. The shape is checked by looking
# at it, which is the only honest way to check a shape.
got=$(body "$H/f/$FILM/share?as=$OWNER")
echo "$got" | grep -q 'id="share"' && echo "$got" | grep -q '/share.js' \
  && ok "an editor is served the share window" || no "an editor is served the share window" "not served"
[ "$(code "$H/share.js")" = 200 ] && ok "and the window itself is served" || no "and the window itself is served" "not 200"

[ "$(code "$H/f/$FILM/share?as=$STRANGER")" = 403 ] \
  && ok "a stranger cannot open the share window" || no "a stranger cannot open the share window" "not 403"

# The viewer has linked to `?people=1` since Stage 1; a live link is worth more
# than a tidy one, so it still goes somewhere.
[ "$(code "$H/f/$FILM?people=1&as=$OWNER")" = 302 ] \
  && ok "the old people address still goes somewhere" || no "the old people address still goes somewhere" "not 302"

# **The key is kept now** — his call. Copy link cannot work from a hash.
sent='{"people":[],"links":[{"hash":"'$(printf 'copyable' | shasum -a 256 | cut -d" " -f1)'","key":"AAAAAAAAAAAAAAAAAAAAAAAA","role":"viewer","expires":null,"salt":null,"pass":null}],"invites":[]}'
got=$(body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER")
echo "$got" | grep -q "AAAAAAAAAAAAAAAAAAAAAAAA" \
  && ok "a link's address is kept, so it can be copied again" || no "a link's address is kept, so it can be copied again" "$got"

# And the button says which of the two states the film is in, without opening it.
got=$(body "$H/f/$FILM?as=$OWNER")
echo "$got" | grep -q 'sharebtn open' \
  && ok "the chrome shows a film is out in the world" || no "the chrome shows a film is out in the world" "no globe"
body "$H/f/$FILM?as=$DIRECTOR" | grep -qv "sharebtn" \
  && ok "and a viewer is offered no share button at all" || no "and a viewer is offered no share button at all" "offered one"

# **Share works on every page, not two of them.** His report, 2026-09-08: a link
# copied anywhere but the film's page or the shot list came back pointing at the
# film's front door. Two halves to that, and this is the half a server can hold —
# the panel has to be *on* a page before it can know which page it is on, and it
# was only ever sent to the film's page and the app.
got=$(body "$H/f/$FILM/bible?as=$OWNER")
echo "$got" | grep -q '/share.js' && echo "$got" | grep -q 'window.HUB' \
  && ok "a record page carries the share window too" || no "a record page carries the share window too" "not carried"
echo "$got" | grep -q 'href="/f/'"$FILM"'/share?from=bible"' \
  && ok "and its button says where it was pressed" || no "and its button says where it was pressed" "no from"
if body "$H/f/$FILM/bible?as=$DIRECTOR" | grep -q "share.js"; then
  no "a viewer on a record page is sent none of it" "sent it"
else
  ok "a viewer on a record page is sent none of it"
fi

# The film's own address, on the page the button lands on with nothing running.
body "$H/daybreak/share?as=$OWNER" | grep -q '"base":"/daybreak"' \
  && ok "the share page knows the film's own address" || no "the share page knows the film's own address" "no base"

# ---- unlisted links: his sharing model --------------------------------------
#
# A link must open a film with **no sign-in at all**, which is why it is served
# from a host with no Access in front of it. So these ask as that host.
SHARE=(-H "x-hub-host: share.your-domain.example")
PKEY="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
PHASH=$(printf '%s' "$PKEY" | shasum -a 256 | cut -d' ' -f1)
SALT="0123456789abcdef0123456789abcdef"
PWORD="opensesame"
PPASS=$(printf '%s' "$SALT$PWORD" | shasum -a 256 | cut -d' ' -f1)
sent=$(printf '{"people":[],"links":[{"hash":"%s","role":"viewer","expires":null}],"invites":[]}' "$HASH")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null

[ "$(code "${SHARE[@]}" "$H/f/$FILM?k=$KEY")" = 200 ] \
  && ok "an unlisted link opens the film with no sign-in" || no "an unlisted link opens the film with no sign-in" "not 200"
[ "$(code "${SHARE[@]}" "$H/f/$FILM")" = 404 ] \
  && ok "…and without the key there is simply nothing there" || no "…and without the key there is simply nothing there" "not 404"
[ "$(code "${SHARE[@]}" "$H/f/$FILM?as=$OWNER")" = 404 ] \
  && ok "…and it will not believe you are him" || no "…and it will not believe you are him" "not 404"
[ "$(code "${SHARE[@]}" -X PUT -d x "$H/f/$FILM/api/log/0000000000000001-000000000000000a.log?k=$KEY")" = 403 ] \
  && ok "…and every write is refused there" || no "…and every write is refused there" "not 403"

# **A link holder can pass the link on.** His ask, 2026-09-08: they get the same
# Share button, and it hands them the link. It has to come from the page — every
# address inside the film is a plain one with no key on it, so the address bar
# gives them something that opens nothing, and the cookie that remembers the key
# is HttpOnly and cannot be read by the page.
got=$(body "${SHARE[@]}" "$H/f/$FILM?k=$KEY")
echo "$got" | grep -q '/share.js' \
  && ok "a link holder is sent the share window" || no "a link holder is sent the share window" "not sent"
echo "$got" | grep -q "\"linkKey\":\"$KEY\"" \
  && ok "…and the key it came in on, which the page cannot read for itself" \
  || no "…and the key it came in on, which the page cannot read for itself" "no key"
echo "$got" | grep -q 'class="sharebtn open"' \
  && ok "…and a Share button saying the film is out in the world" \
  || no "…and a Share button saying the film is out in the world" "no button"
# **Nobody else's address is in it.** The window tells an editor who owns the
# film so it can refuse to demote him; a link holder has no business with that.
echo "$got" | grep -q '"owners"' \
  && no "a link holder is told nobody's address" "owners are in the page" \
  || ok "a link holder is told nobody's address"
[ "$(code "${SHARE[@]}" "$H/f/$FILM/share?k=$KEY")" = 200 ] \
  && ok "…and the share address opens for them rather than refusing" \
  || no "…and the share address opens for them rather than refusing" "not 200"
# A record page is the same story — that is where he found it.
body "${SHARE[@]}" "$H/f/$FILM/bible?k=$KEY" | grep -q "\"linkKey\":\"$KEY\"" \
  && ok "…on a record page too" || no "…on a record page too" "no key"

# **The circle says somebody, not nothing.** His instruction, 2026-09-08: a
# person with no sign-in was drawn as `·`, which names nobody and reads as a
# fault. A mark in the same hand as the rest, and the menu behind it still says
# *Opened with a link*.
got=$(body "${SHARE[@]}" "$H/f/$FILM?k=$KEY")
echo "$got" | grep -q 'class="fh-avatar" title="You" aria-label="You"><svg' \
  && ok "somebody with no sign-in is drawn as a person" \
  || no "somebody with no sign-in is drawn as a person" "no mark"
echo "$got" | grep -q '>&#183;<\|>·<' \
  && no "…and the full stop is gone" "still a dot" \
  || ok "…and the full stop is gone"
echo "$got" | grep -q "Opened with a link" \
  && ok "…and the menu still says how they got in" \
  || no "…and the menu still says how they got in" "not said"
# His own circle is unchanged: two letters, no mark.
body "$H/f/$FILM?as=$OWNER" | grep -q 'class="fh-avatar" title="You" aria-label="You">OW\?<\|aria-label="You">O<' \
  && ok "his own circle still carries his initials" \
  || no "his own circle still carries his initials" "no initials"

# **A viewer signed in by name is not given one.** They hold no key, so there is
# nothing for them to copy; a button that could only hand over an address
# needing a sign-in would be worse than no button.
got=$(body "$H/f/$FILM?as=$DIRECTOR")
echo "$got" | grep -q "share.js" \
  && no "a signed-in viewer is still offered nothing" "sent the window" \
  || ok "a signed-in viewer is still offered nothing"

# a link he has put a password on
sent=$(printf '{"people":[],"links":[{"hash":"%s","role":"viewer","expires":null,"salt":"%s","pass":"%s"}],"invites":[]}' "$PHASH" "$SALT" "$PPASS")
body -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null

got=$(body "${SHARE[@]}" "$H/f/$FILM?k=$PKEY")
echo "$got" | grep -q "Password" && ok "a link with a password asks for it first" || no "a link with a password asks for it first" "no prompt"
# **Dressed as the film, always** — his ruling 2026-09-16. By now the card
# carries Notion's red mark (set three hundred lines up), and that is what
# the door wears; the manifest stand-in is proven at the top of the run.
echo "$got" | grep -q -- "--accent:#C2554D" \
  && ok "…and the door wears the film's colour" || no "…and the door wears the film's colour" "wore: $(echo "$got" | grep -o 'gatepass"[^>]*' | head -c 120)"
echo "$got" | grep -q 'class="filmicon"' \
  && ok "…and its mark" || no "…and its mark" "no mark"
echo "$got" | grep -q 'class="mark"' \
  && ok "…under his wordmark" || no "…under his wordmark" "no wordmark"
# **And a locked link still unfurls** — his ruling, 2026-09-19, reversing
# 2026-09-02's "the gate names no film": the preview carries the title and
# the cover, the page itself stays locked, and the cover is served before the
# gate so whatever draws the preview can fetch it without the password.
# (the film has been renamed Daybreak by this point in the run)
echo "$got" | grep -q '<meta property="og:title" content="Daybreak">' \
  && ok "a locked link's preview names the film" || no "a locked link's preview names the film" "no og:title"
echo "$got" | grep -q "og:image" \
  && ok "…and carries its cover" || no "…and carries its cover" "no og:image"
[ "$(code "${SHARE[@]}" "$H/f/$FILM/icon.svg?k=$PKEY")" != 401 ] \
  && ok "…and the mark is served ahead of the gate" || no "…and the mark is served ahead of the gate" "401"
[ "$(code "${SHARE[@]}" -X POST --data-urlencode "password=wrong" "$H/f/$FILM?k=$PKEY")" = 401 ] \
  && ok "…and refuses the wrong one" || no "…and refuses the wrong one" "not 401"
JAR2=$(mktemp)
curl -s -o /dev/null -c "$JAR2" "${SHARE[@]}" -X POST --data-urlencode "password=$PWORD" "$H/f/$FILM?k=$PKEY"
grep -q "hubpass" "$JAR2" && ok "…and lets the right one through" || no "…and lets the right one through" "no cookie"
[ "$(curl -s -o /dev/null -b "$JAR2" -w "%{http_code}" "${SHARE[@]}" "$H/f/$FILM?k=$PKEY")" = 200 ] \
  && ok "…and does not ask again" || no "…and does not ask again" "not 200"
rm -f "$JAR2"

# ---- nothing here is for the open web ---------------------------------------
got=$(body "$H/robots.txt")
echo "$got" | grep -q "Disallow: /" && ok "robots.txt refuses every crawler" || no "robots.txt refuses every crawler" "$got"
curl -s -D- -o /dev/null "$H/health" | grep -qi "x-robots-tag: noindex" \
  && ok "every answer carries noindex" || no "every answer carries noindex" "header missing"

# ---- the client is actually served ------------------------------------------
[ "$(code "$H/shotlister_web.wasm")" = 200 ] && ok "the engine is served to the browser" || no "the engine is served to the browser" "not 200"
[ "$(code "$H/hub.css")" = 200 ] && ok "the stylesheet is served" || no "the stylesheet is served" "not 200"
[ "$(code "$H/copy.js")" = 200 ] && ok "the copier is served" || no "the copier is served" "not 200"
got=$(body "$H/f/$MFILM?as=$OWNER")
echo "$got" | grep -q 'data-copy' \
  && ok "a value on the film's page can be copied" || no "a value on the film's page can be copied" "no data-copy"
echo "$got" | grep -q 'src="/copy\.js?' \
  && ok "and the page loads what does the copying" || no "and the page loads what does the copying" "no script"

# **Every front-of-house page must link `front.css`, and it is not enough that
# it looks right in a harness.** The shelf and the photograph picker were moved
# to the new markup and shipped without it — no stylesheet at all, and no
# transition either, because a cross-document one needs both pages to opt in.
# Nothing caught it: the checks read content, and content was fine.
for road in "" "/bible" "/camera" "/people" "/documents" "/crew"; do
  what=$(body "$H/f/$MFILM$road?as=$OWNER")
  echo "$what" | grep -q 'href="/front\.css?' \
    && ok "the front of house is styled at ${road:-/}" \
    || no "the front of house is styled at ${road:-/}" "no front.css"
done
shelf=$(body "$H/?as=$OWNER")
echo "$shelf" | grep -q 'href="/front\.css?' \
  && ok "and so is the shelf" || no "and so is the shelf" "no front.css"
[ "$(code "$H/front.css")" = 200 ] && ok "front.css is served" || no "front.css is served" "not 200"
[ "$(code "$H/deep.js")" = 200 ] && ok "the in-page mover is served" || no "the in-page mover is served" "not 200"
# **The addresses must stay real.** `deep.js` swaps pages in without a reload,
# and the whole safety of that rests on every one of them still being a page a
# browser can simply open. Typing the address is what a crew member does when a
# link is pasted into a message.
what=$(body "$H/f/$MFILM/camera?as=$OWNER")
echo "$what" | grep -q "Capture Resolution" \
  && ok "a record page still answers on its own" || no "a record page still answers on its own" "no camera page"
echo "$what" | grep -q 'src="/deep\.js?' \
  && ok "and carries the mover" || no "and carries the mover" "no deep.js"
echo "$what" | grep -q 'data-deep="home"' \
  && ok "the way back out is marked" || no "the way back out is marked" "no data-deep"
home=$(body "$H/f/$MFILM?as=$OWNER")
echo "$home" | grep -q 'data-deep="record"' \
  && ok "and the way in" || no "and the way in" "no data-deep"
# **The way to the other films is a drawing with a word behind it.** His ask,
# 2026-09-04: the button is a back arrow, and *Projects* slides out from behind
# it on hover. Both halves are worth holding — a bare arrow beside a film you
# are already looking at says nothing (his 2026-09-02 ruling), and a word with
# no drawing is what this replaced. The slide itself is a CSS transition and
# nothing a line-based check can see; that it has both parts to slide, it can.
echo "$home" | grep -q 'class="back"[^>]*>.*<svg' \
  && ok "the way to the other films is drawn" || no "the way to the other films is drawn" "no arrow"
echo "$home" | grep -q 'class="bw">Projects<' \
  && ok "…and still says which films" || no "…and still says which films" "no word"
# **And it is a door on a phone too.** His report, 2026-09-23: the rail's top is
# hidden in the phone's sheet and the home-screen app has no back button, so a
# film had no way out. The phone's bar leads with the arrow, on both doors.
echo "$home" | grep -q 'class="fh-topbar">[[:space:]]*<a class="tback" href="/"' || echo "$home" | tr -d '\n' | grep -q 'class="fh-topbar">[[:space:]]*<a class="tback" href="/"' \
  && ok "…and the phone's bar leads with the way back" || no "…and the phone's bar leads with the way back" "no tback"
grep -q 'class="tback" href="${esc(back)}"' "$HERE/public/film.js" \
  && ok "…in the app's bar as well" || no "…in the app's bar as well" "film.js has no tback"
grep -q '\.railtop \.back::before{content:""' "$HERE/public/front.css" \
  && ok "…and the desk's arrow is a bigger place to press than it draws" || no "…and the desk's arrow is a bigger place to press than it draws" "no target"
# **The shot list still opens in place, by its own route.** It wakes the engine
# out of sight and shows it once drawn, so it stays marked apart from the record
# pages — the mark moved from the door onto the rail's row when the door went.
echo "$home" | grep -q 'data-deep="app"[^>]*href="[^"]*/shotlist"' \
  && ok "the shot list opens in place" || no "the shot list opens in place" "not marked"
# And it must stay an address a person can simply open.
app=$(body "$H/f/$MFILM/shotlist?as=$OWNER")
echo "$app" | grep -q 'id="film"' \
  && ok "the app still answers on its own" || no "the app still answers on its own" "no film box"
echo "$app" | grep -q 'window.HUB' \
  && ok "and tells itself which film it is" || no "and tells itself which film it is" "no HUB"
# **The app carries the two files the front of house needs, or Home is a page
# load.** Arriving here by a link or a reload used to leave the app without
# `deep.js` to catch the way out and without `front.css` to say how it looks —
# so the one move he pressed most often was the one that never animated.
echo "$app" | grep -q 'src="/deep\.js?' \
  && ok "the app can move without leaving the document" \
  || no "the app can move without leaving the document" "no deep.js"
echo "$app" | grep -q 'href="/front\.css?' \
  && ok "and knows how that move should look" \
  || no "and knows how that move should look" "no front.css"
# **Brought back by a door, the app goes to the screen the door named.** It
# is put away when he leaves it and swapped back when he presses one of its
# rows — and it came back on whatever screen it was left on, so Locations
# opened the Shot List. His report, 2026-09-10. Needs a browser to watch; this
# holds the wiring: `deep.js` says `entering` after pushing the address, and
# `film.js` reads the screen off the address. Back and forward are the same
# move, for any of the four addresses rather than only the shot list.
grep -q 'tellApp();' "$HERE/public/deep.js" && grep -q 'new Event("entering")' "$HERE/public/deep.js" \
  && grep -q 'addEventListener("entering"' "$HERE/public/film.js" \
  && ok "a door into the app it has already opened names the screen" \
  || no "a door into the app it has already opened names the screen" "not wired"
grep -q 'shotlist|locations|boards|schedule)\\/?\$/.test(location.pathname)' "$HERE/public/deep.js" \
  && ok "…and Back inside the app knows all four addresses" \
  || no "…and Back inside the app knows all four addresses" "only the shot list"

# **A scene picked from the list is scrolled to, not filtered to.** His ask,
# 2026-09-10: "I'd rather scroll down with a smooth animation, the same way
# the actual shotlister app does, to that scene's shots within the table. Same
# goes for storyboard view and document view." Needs a browser to watch —
# checked by hand against his film at desk and phone width — so this holds
# the shape: every view draws every scene under a band, nothing narrows the
# page to one scene, and the glide is the app's own.
grep -q 'function goToScene' "$HERE/public/film.js" && grep -q 'function glide' "$HERE/public/film.js" \
  && ok "picking a scene carries the page to it" || no "picking a scene carries the page to it" "no goToScene"
grep -q 'all.filter((g) => g.key === chosen.id)' "$HERE/public/film.js" \
  && no "…and no view narrows to the picked scene" "shownGroups still filters" \
  || ok "…and no view narrows to the picked scene"
grep -q 'return sceneBand(g) + `<div class="cards' "$HERE/public/film.js" \
  && ok "…and the storyboard draws every scene under its band" \
  || no "…and the storyboard draws every scene under its band" "one scene still"
grep -q 'All scenes' "$HERE/public/film.js" \
  && no "…and there is no All scenes to un-narrow with" "still drawn" \
  || ok "…and there is no All scenes to un-narrow with"
# **A commercial's sections are told apart the way the Mac tells them apart.**
# His finding on Harbour Light Affair, 2026-09-19: three scripts in three
# sections were not telling apart while scrolling. The section's colour runs
# down every band, row and card of its run (`runStyle` → `.insec`), the head
# is tinted and set in it, and the Document page opens each run with a
# chapter head. A bare section wears the engine's own colour by position,
# so the portal and the Mac never disagree. Checked by eye against his film;
# this holds the shape.
grep -q 'function runStyle' "$HERE/public/film.js" && grep -q 'insec' "$HERE/public/hub.css" \
  && grep -q 'class="sceneband${run.cls}"' "$HERE/public/film.js" \
  && grep -q 'class="trow${row.struck ? " struck" : ""}${run.cls}"' "$HERE/public/film.js" \
  && grep -q 'class="lrow${row.struck ? " struck" : ""}${run.cls}"' "$HERE/public/film.js" \
  && grep -q 'class="cards${run.cls}"' "$HERE/public/film.js" \
  && ok "a section's colour runs down every band, row and card of its run" \
  || no "a section's colour runs down every band, row and card of its run" "runStyle missing somewhere"
grep -q 'class="docsection' "$HERE/public/film.js" && grep -q '^\.docsection' "$HERE/public/hub.css" \
  && ok "…and the Document page opens each section with a chapter head" \
  || no "…and the Document page opens each section with a chapter head" "no docsection"
grep -q '"#2B6CB0", "#B4531B", "#2F7A44", "#7B4BC4", "#A33574", "#2C7A7B", "#9A6B10", "#4C51BF"' "$HERE/public/film.js" \
  && grep -q '"#2B6CB0", "#B4531B", "#2F7A44", "#7B4BC4",' "$HERE/../engine/src/doc.rs" \
  && grep -q '"#A33574", "#2C7A7B", "#9A6B10", "#4C51BF",' "$HERE/../engine/src/doc.rs" \
  && ok "…and a bare section wears the engine's own colours, in the engine's order" \
  || no "…and a bare section wears the engine's own colours, in the engine's order" "the two lists differ"
# **The schedule stays the schedule when a scene on it is pressed.** His
# report, 2026-09-10: "if I click on a day it takes me to shot list, and I
# have to go back to schedule." A press lights it; a double press opens it in
# the Shot List, the Mac's own gesture.
grep -q 'data-jump' "$HERE/public/film.js" \
  && no "a press on the schedule stays on the schedule" "a stripe still jumps" \
  || ok "a press on the schedule stays on the schedule"
grep -q 'data-strip' "$HERE/public/film.js" && grep -q 'addEventListener("dblclick", () => {' "$HERE/public/film.js" \
  && ok "…and a double press opens the scene in the Shot List" \
  || no "…and a double press opens the scene in the Shot List" "no double press"
[ "$(code "$H/f/$MFILM/api/state?as=$OWNER")" = 200 ] \
  && ok "the change logs are listed" || no "the change logs are listed" "no state"

# **The two stylesheets must not name the same thing.** `hub.css` was written
# first and named things plainly; the front of house reached for the same plain
# words, and on 2026-09-04 that cost four faults in an afternoon — the worst of
# them handing `<body>` the script panel's paper, which is what drew the white
# bars down the sides of his phone. The front of house's own names carry `fh-`
# now, and this holds the line. `hub/collide.py` says which names are still
# shared and why.
if python3 "$HERE/collide.py" >/dev/null 2>&1; then
  ok "the two stylesheets do not fight over a name"
else
  no "the two stylesheets do not fight over a name" "$(python3 "$HERE/collide.py" | tail -n +2 | head -1 | xargs)"
fi

# ---- his bible, on the Visual Bible page -------------------------------------
# His instruction, 2026-09-05: the bible he writes in Notion belongs on *"the
# visual language bible web app page"*. A Project Docs row ticked Hub and named
# `Visual Bible` used to arrive as a section of its own under Details, beside
# the built-in Visual Bible under Look — two rows of the same name, one holding
# the two paragraphs off the film's Notion page and the other holding the forty
# pictures. `refresh.py` folds it onto `bible` now.
#
# **Last in the file on purpose.** It rewrites `front.json`, and a check that
# seeds a value can break another one hundreds of lines away.
cat > /tmp/hubcheck-bible.json <<'JSON'
[{"t":"h1","r":[{"s":"Visual Language"}]},
 {"t":"columns","k":[{"t":"column","k":[{"t":"img","src":"0102030405060708090a0b0c0d0e0f10.jpg","cap":"Swallow"}]}]},
 {"t":"li","r":[{"s":"Hard lines belong to the mansion"}]}]
JSON
put "p/$MFILM/pages/bible.json" /tmp/hubcheck-bible.json
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-bible-front.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-bible-front.json'))
f['sections'] = [{'slug': 'bible', 'name': 'Visual Bible',
                  'title': 'Call Her Back - Visual Language Bible', 'blocks': 3}]
f['look'] = 'Controlled to freedom.'
# **Not the ratio.** Since 2026-09-16 the film's shape is the film's — a
# number written here is overridden by the replayed film, on purpose.
json.dump(f, open('/tmp/hubcheck-bible-front.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-bible-front.json
rm -f /tmp/hubcheck-bible.json /tmp/hubcheck-bible-front.json

got=$(body "$H/f/$MFILM/bible?as=$OWNER")
echo "$got" | grep -q "Hard lines belong to the mansion" \
  && ok "his Notion bible is drawn on the Visual Bible page" \
  || no "his Notion bible is drawn on the Visual Bible page" "not drawn"
! echo "$got" | grep -q "Controlled to freedom" && body "$H/f/$MFILM?as=$OWNER" | grep -q "Controlled to freedom" \
  && ok "and the film's own paragraphs are on its front page, not here" \
  || no "and the film's own paragraphs are on its front page, not here" "the prose is on the bible, or gone"
echo "$got" | grep -q "0102030405060708090a0b0c0d0e0f10.jpg" \
  && ok "and its pictures are served from the film's own media" \
  || no "and its pictures are served from the film's own media" "no picture"
echo "$got" | grep -q "Call Her Back - Visual Language Bible" \
  && ok "and the page says which Notion page it came from" \
  || no "and the page says which Notion page it came from" "no source line"

# **Cropped to the film's shape, and openable.** His rules, 2026-09-05: conform
# everything to the project aspect ratio, and give a picture a preview when it
# is clicked. The crop is a CSS variable the page has to carry — a stylesheet
# cannot invent it — and the preview is a file the page has to load. The
# shape is the film's own (Daybreak's logs say 2.39), asked of the film.
echo "$got" | grep -q -- "--filmratio:2.39" \
  && ok "the page carries the film's shape for its pictures" \
  || no "the page carries the film's shape for its pictures" "no --filmratio"
echo "$got" | grep -q 'src="/look\.js?' \
  && ok "and a picture on it can be opened" \
  || no "and a picture on it can be opened" "no look.js"
[ "$(code "$H/look.js")" = 200 ] \
  && ok "and that file is served" || no "and that file is served" "not 200"
# **One lightbox for every picture** (2026-09-10). A picture on the page wears
# `data-look`; so does every tile on a reference board, a scene's Reference
# panel and a location's photographs — the app draws those in the browser, so
# the wiring is read off `film.js` rather than off a page. A published deck's
# pictures sit inside a shadow root, which only `composedPath` sees through.
echo "$got" | grep -q 'data-look="page"' \
  && ok "the page's pictures are marked for the lightbox" \
  || no "the page's pictures are marked for the lightbox" "no data-look on the figure"
[ "$(grep -c 'class="tile" data-look=' "$HERE/public/film.js")" -ge 4 ] \
  && ok "so are the walls of references and photographs in the app" \
  || no "so are the walls of references and photographs in the app" "fewer than four marked walls in film.js"
grep -q 'composedPath' "$HERE/public/look.js" \
  && ok "and a picture in a published deck can be reached through its seal" \
  || no "and a picture in a published deck can be reached through its seal" "look.js has no composedPath"
grep -q '\[data-open\], \[data-nolook\], \.popout' "$HERE/public/look.js" \
  && ok "while a shot's frame still opens the app's own pop-out" \
  || no "while a shot's frame still opens the app's own pop-out" "look.js does not stand aside for data-open"

# **The icon set has one source** (`src/icons.js`); `public/icons.js` is the
# browser's copy, and the two must say the same thing.
if node --input-type=module -e '
  import { ROW_ICONS, ICON_CHOICES, SHELF_ICONS } from "'"$HERE"'/src/icons.js";
  import { readFileSync } from "node:fs";
  const w = {}; new Function("window", readFileSync("'"$HERE"'/public/icons.js", "utf8"))(w);
  const same = JSON.stringify([ROW_ICONS, ICON_CHOICES, SHELF_ICONS]) === JSON.stringify([w.ROW_ICONS, w.ICON_CHOICES, w.SHELF_ICONS]);
  process.exit(same && ICON_CHOICES.every((n) => ROW_ICONS[n]) ? 0 : 1);'; then
  ok "the icon set in the browser is the set on the server"
else
  no "the icon set in the browser is the set on the server" "public/icons.js differs from src/icons.js"
fi

# **Said once.** The whole point of folding it is that the rail does not carry
# two rows called Visual Bible in two different groups.
rail=$(body "$H/f/$MFILM?as=$OWNER")
[ "$(echo "$rail" | grep -o '<span class="nm">Visual Bible</span><' | wc -l | tr -d ' ')" = 1 ] \
  && ok "the rail names the Visual Bible once, not twice" \
  || no "the rail names the Visual Bible once, not twice" "$(echo "$rail" | grep -o '<span class="nm">Visual Bible</span><' | wc -l | tr -d ' ') rows"

# **A section he names anything else is still a section of its own.** Folding
# the bible must not have folded everything.
cat > /tmp/hubcheck-over.json <<'JSON'
[{"t":"p","r":[{"s":"Two grip trucks and a genny."}]}]
JSON
put "p/$MFILM/pages/overheads.json" /tmp/hubcheck-over.json
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-over-front.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-over-front.json'))
f['sections'] = f.get('sections', []) + [{'slug': 'overheads', 'name': 'Overheads',
                                          'title': 'Overheads', 'blocks': 1}]
json.dump(f, open('/tmp/hubcheck-over-front.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-over-front.json
rm -f /tmp/hubcheck-over.json /tmp/hubcheck-over-front.json
echo "$(body "$H/f/$MFILM?as=$OWNER")" | grep -q ">Overheads<" \
  && ok "a section named anything else keeps its own row" \
  || no "a section named anything else keeps its own row" "no row"
echo "$(body "$H/f/$MFILM/overheads?as=$OWNER")" | grep -q "Two grip trucks" \
  && ok "and its page still opens" || no "and its page still opens" "not drawn"

# ---- a page written by an agent, not by Notion -------------------------------
#
# **The second road onto the record.** Until now the only thing that could write
# a page beside a film was `refresh.py` reading a Hub-ticked Notion row — so an
# agent that had just worked out a film's visual language had to ask him to make
# a Notion page first and then wait for a refresh. `set_page` is the other way
# in, and what these hold is that it lands in exactly the same place: a real
# address, a row in the rail, and a page drawn by the same code that draws his.
got=$(said "$(tell '{"jsonrpc":"2.0","id":30,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Lighting Plan","subtitle":"Written from an AI","markdown":"# Night Exteriors\n\nSodium **practicals** only, and a [rented condor](https://example.com/condor).\n\n- Two 18Ks through the window\n  - half CTB on the left\n- Nothing on the faces\n\n> Let it go black.\n\n| Scene | Unit |\n| --- | --- |\n| 12 | Condor |\n\n![Elsewhere](https://elsewhere.example/x.jpg)"}}}')")
echo "$got" | grep -q "Lighting Plan is up" \
  && ok "an AI can make a page on a film with no Notion in it" \
  || no "an AI can make a page on a film with no Notion in it" "$got"
# **A picture that cannot be drawn is said, not swallowed.** `pictureUrl` builds
# an address inside the film, so somebody else's server has nowhere to go.
echo "$got" | grep -q "Dropped: picture" \
  && ok "…and a picture pointing elsewhere is dropped out loud" \
  || no "…and a picture pointing elsewhere is dropped out loud" "$got"

page=$(body "$H/f/$MFILM/lighting-plan?as=$OWNER")
echo "$page" | grep -q "Night Exteriors" && ok "the page opens at an address made from its name" \
  || no "the page opens at an address made from its name" "not drawn"
echo "$page" | grep -q "Sodium practicals only" \
  && ok "…with the emphasis markers taken off rather than printed" \
  || no "…with the emphasis markers taken off rather than printed" "$(echo "$page" | grep -o 'Sodium[^<]*')"
echo "$page" | grep -q 'href="https://example.com/condor"' && ok "…its links kept" || no "…its links kept" "no link"
echo "$page" | grep -q "half CTB on the left" && ok "…its nested list kept" || no "…its nested list kept" "no nesting"
echo "$page" | grep -q "<table" && ok "…and its table drawn as a table" || no "…and its table drawn as a table" "no table"
echo "$(body "$H/f/$MFILM?as=$OWNER")" | grep -q ">Lighting Plan<" \
  && ok "the film's rail carries the new page" || no "the film's rail carries the new page" "no row"

got=$(said "$(tell '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Share","markdown":"anything"}}}')")
echo "$got" | grep -qi "already an address" \
  && ok "a page cannot be given a name something else already answers to" \
  || no "a page cannot be given a name something else already answers to" "$got"

# **Whoever made a page owns it, and the two roads never fight over one.** A
# Notion-made section is seeded here rather than borrowed from the checks above,
# so this holds whatever else the film happens to be carrying.
cat > /tmp/hubcheck-prep.json <<'JSON'
[{"t":"p","r":[{"s":"Truck loads at six."}]}]
JSON
put "p/$MFILM/pages/prep-notes.json" /tmp/hubcheck-prep.json
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-prep-front.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-prep-front.json'))
f['sections'] = f.get('sections', []) + [{'slug': 'prep-notes', 'name': 'Prep Notes',
                                          'title': 'From his Notion page'}]
json.dump(f, open('/tmp/hubcheck-prep-front.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-prep-front.json
rm -f /tmp/hubcheck-prep.json /tmp/hubcheck-prep-front.json
# **Removing is destructive; taking over is not.** A page Notion made may be
# written here — his decision of 2026-09-04 made the portal the source, and his
# own bible came from Notion, so refusing the write refused the very thing he
# asked for. Deleting one is still Notion's to do.
got=$(said "$(tell '{"jsonrpc":"2.0","id":33,"method":"tools/call","params":{"name":"remove_page","arguments":{"slug":"prep-notes"}}}')")
echo "$got" | grep -qi "named in Notion" \
  && ok "an agent cannot delete a page Notion still names" \
  || no "an agent cannot delete a page Notion still names" "$got"

# A second Notion page, so the take-over below leaves the one above alone.
cat > /tmp/hubcheck-call.json <<'JSON'
[{"t":"p","r":[{"s":"Crew call is at seven."}]}]
JSON
put "p/$MFILM/pages/call-notes.json" /tmp/hubcheck-call.json
body "$H/f/$MFILM/api/front?as=$OWNER" > /tmp/hubcheck-call-front.json
python3 -c "
import json
f = json.load(open('/tmp/hubcheck-call-front.json'))
f['sections'] = f.get('sections', []) + [{'slug': 'call-notes', 'name': 'Call Notes',
                                          'title': 'From his Notion page'}]
json.dump(f, open('/tmp/hubcheck-call-front.json', 'w'))
"
put "p/$MFILM/front.json" /tmp/hubcheck-call-front.json
rm -f /tmp/hubcheck-call.json /tmp/hubcheck-call-front.json
got=$(said "$(tell '{"jsonrpc":"2.0","id":32,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Call Notes","markdown":"Crew call moved to six."}}}')")
echo "$got" | grep -qi "now written here" \
  && ok "an agent may take over a page Notion made, and is told it has" \
  || no "an agent may take over a page Notion made, and is told it has" "$got"
echo "$(body "$H/f/$MFILM/call-notes?as=$OWNER")" | grep -q "Crew call moved to six" \
  && ok "…and the page shows what the agent wrote" \
  || no "…and the page shows what the agent wrote" "not drawn"
# **The logline is the Logline box, and the old heading only while it is
# empty** (2026-10-05). `typedWords` in src/notion.js is the same rule.
python3 - "$HERE" <<'PY' && ok "refresh.py reads the Logline box first, the heading only while it is empty" || no "refresh.py reads the Logline box first, the heading only while it is empty" "wrong words"
import sys
sys.path.insert(0, sys.argv[1])
import refresh
box = {"properties": {"Logline": {"type": "rich_text", "rich_text": [{"plain_text": "From the box."}]}}}
empty = {"properties": {"Logline": {"type": "rich_text", "rich_text": []}}}
none = {"properties": {}}
assert refresh.typed_words(box, {"logline": "From the heading."})["logline"] == "From the box."
assert refresh.typed_words(empty, {"logline": "From the heading."})["logline"] == "From the heading."
assert refresh.typed_words(none, {"logline": "From the heading."})["logline"] == "From the heading."
PY

# **The director's note and the visual language are boxes too** (2026-10-05,
# his templates decision): box first, heading while it is empty, paragraph
# breaks as single spaces; the record's facts lay onto the card the same way.
python3 - "$HERE" <<'PY' && ok "refresh.py reads Director's Note and Visual Language boxes first, as one line" || no "refresh.py reads Director's Note and Visual Language boxes first, as one line" "wrong words"
import sys
sys.path.insert(0, sys.argv[1])
import refresh
row = {"properties": {"Director's Note": {"type": "rich_text", "rich_text": [{"plain_text": "One.\n\nTwo."}]},
                      "Visual Language": {"type": "rich_text", "rich_text": []}}}
said = refresh.typed_words(row, {"logline": "", "note": "From the heading.", "look": "Look heading."})
assert said["note"] == "One. Two.", said
assert said["look"] == "Look heading.", said
card = {"note": "One. Two.", "look": ""}
took = refresh.from_record(card, {"directors_note": {"value": "One.\n\nTwo."}, "visual_language": {"value": "Wide."}})
assert took == ["look"], (took, card)
assert card["look"] == "Wide." and card["note"] == "One. Two."
PY
grep -q 'note: "Director'"'"'s Note", look: "Visual Language"' "$HERE/src/notion.js" \
  && ok "src/notion.js reads the same two boxes as refresh.py" \
  || no "src/notion.js reads the same two boxes as refresh.py" "TYPED differs"

# **More than one person per credit, and more credits; a field the project
# hides stays off the card** (2026-10-05, his asks). The record's `credits`
# list and the readout's `hidden` — refresh.py and src/facts.js, one rule.
python3 - "$HERE" <<'PY' && ok "refresh.py lays every credit the project shows, and leaves hidden ones off" || no "refresh.py lays every credit the project shows, and leaves hidden ones off" "wrong card"
import sys
sys.path.insert(0, sys.argv[1])
import refresh
facts = {"director": {"value": "Ivy Sterling & Robin Vale Arden"},
         "credits": {"value": [{"role": "Director", "people": ["Ivy Sterling", "Robin Vale Arden"]},
                               {"role": "Executive Producer", "people": ["Owen Fairweather", "Tess Marlow"]},
                               {"role": "Writer", "people": ["W"]}, {"role": "<script>", "people": ["x"]}]}}
card = {"director": "Notion's", "logline": "Words", "credits": []}
took = refresh.from_record(card, facts, ["logline", "credit:Writer"])
assert card["director"] == "Ivy Sterling & Robin Vale Arden", card
assert card["credits"] == [{"role": "Executive Producer", "people": ["Owen Fairweather", "Tess Marlow"]}], card
assert card["logline"] == "", "hidden: left off the card"
assert refresh.from_record(card, facts, ["logline", "credit:Writer"]) == [], "the same again moves nothing"
assert refresh.from_record({}, {}, []) == [], "no record, nothing laid"
PY
node --input-type=module - "$HERE" <<'JS' && ok "…and the worker lists them the same way, and the page says them" || no "…and the worker lists them the same way, and the page says them" "wrong credits"
const { cardCredits, tidyCredits, creditLine, creditWords } = await import(`${process.argv[2]}/src/credits.js`);
const facts = { credits: { value: [{ role: "Director", people: ["A", "B"] }, { role: "Line Producer", people: ["Lee"] },
  { role: "Executive Producer", people: ["Dan"] }, { role: "Writer", people: ["W"] }] } };
const got = JSON.stringify(cardCredits(facts, ["executive_producer", "credit:Writer"]));
if (got !== JSON.stringify([{ role: "Line Producer", people: ["Lee"] }])) { console.error(got); process.exit(1); }
if (JSON.stringify(tidyCredits([{ role: "<b>", people: ["x"] }, { role: "Writer", people: [" ", " W  "] }]))
    !== JSON.stringify([{ role: "Writer", people: ["W"] }])) process.exit(1);
if (creditLine(["A", "B", "C"]) !== "A, B & C" || creditLine(["A", "B"]) !== "A & B" || creditWords("Writer") !== "Written by") process.exit(1);
JS

# **And the refresh must leave it alone from then on**, or the take-over lasts
# an hour. `both_roads` decides the row; the loop above it decides the contents.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
kept = [{'slug': 'call-notes', 'name': 'Call Notes'}]
already = [{'slug': 'call-notes', 'name': 'Call Notes', 'by': 'mcp'}]
out = refresh.both_roads(already, kept)
sys.exit(0 if len(out) == 1 and out[0].get('by') == 'mcp' else 1)" 2>/dev/null \
  && ok "…and a refresh no longer writes over it" \
  || no "…and a refresh no longer writes over it" "Notion still wins"

# **Which road a page came in on, said plainly**, because an agent has to know
# what it may touch before it touches it.
got=$(said "$(tell '{"jsonrpc":"2.0","id":34,"method":"tools/call","params":{"name":"pages"}}')")
echo "$got" | grep -q '"made_by": "an agent' && ok "pages says which it wrote itself" || no "pages says which it wrote itself" "$got"
echo "$got" | grep -q '"made_by": "Notion"' && ok "…and which are Notion's" || no "…and which are Notion's" "$got"

# A page written here must survive the next refresh — see `both_roads`.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
kept = [{'slug': 'prep-notes', 'name': 'Prep Notes'}]
already = [{'slug': 'lighting-plan', 'name': 'Lighting Plan', 'by': 'mcp'},
           {'slug': 'prep-notes', 'name': 'Prep Notes'}]
out = refresh.both_roads(already, kept)
sys.exit(0 if [s['slug'] for s in out] == ['lighting-plan', 'prep-notes'] else 1)" 2>/dev/null \
  && ok "a refresh from Notion keeps the pages an agent wrote" \
  || no "a refresh from Notion keeps the pages an agent wrote" "swept off"

# **The director is Notion's.** The Projects row's Director relation names
# Crew pages; the refresh reads them by name, joins two the way a credit does,
# and says nothing at all when the row names nobody — so the film's own value
# stands. The console's ask, 2026-09-15.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
crew = [{'id': 'aaaa-1', 'properties': {'Name': {'type': 'title', 'title': [{'plain_text': 'Anna Lee'}]}}},
        {'id': 'bbbb-2', 'properties': {'Name': {'type': 'title', 'title': [{'plain_text': 'Ben Roe'}]}}}]
two = {'properties': {'Director': {'type': 'relation', 'relation': [{'id': 'aaaa1'}, {'id': 'bbbb2'}]}}}
none = {'properties': {'Director': {'type': 'relation', 'relation': []}}}
away = {'properties': {'Director': {'type': 'relation', 'relation': [{'id': 'cccc'}]}}}
fetched = lambda page: {'properties': {'Name': {'type': 'title', 'title': [{'plain_text': 'Cy Dee'}]}}}
sys.exit(0 if refresh.director_of(two, crew) == 'Anna Lee & Ben Roe'
         and refresh.director_of(none, crew) == ''
         and refresh.director_of(away, crew, fetched) == 'Cy Dee' else 1)" 2>/dev/null \
  && ok "a refresh takes the director off the Notion row, and says nothing when it names nobody" \
  || no "a refresh takes the director off the Notion row, and says nothing when it names nobody" "director_of"

# Rewriting is the same call, and the address does not move.
got=$(said "$(tell '{"jsonrpc":"2.0","id":35,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Lighting Plan","markdown":"Day one is a day exterior."}}}')")
echo "$got" | grep -q "rewritten" && ok "writing it again rewrites it in place" || no "writing it again rewrites it in place" "$got"
echo "$(body "$H/f/$MFILM/lighting-plan?as=$OWNER")" | grep -q "Day one is a day exterior" \
  && ok "…and the page shows the new words" || no "…and the page shows the new words" "old words"

# **Folded onto the record's own page, not made a second one.** `Camera Spec
# Sheet` makes the address `camera-spec-sheet` and the page is at `camera`;
# without the fold an agent asking for the spec sheet gets a second one, the
# rail says the words twice, and the page the film already has stays empty.
# That is exactly what the first run of these checks found, on the bible.
got=$(said "$(tell '{"jsonrpc":"2.0","id":36,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Camera Spec Sheet","markdown":"Filters live in the second case."}}}')")
echo "$got" | grep -q "Camera Spec Sheet is up" && ok "a page named after one of the record's own lands on it" \
  || no "a page named after one of the record's own lands on it" "$got"
echo "$(body "$H/f/$MFILM/camera?as=$OWNER")" | grep -q "Filters live in the second case" \
  && ok "…and is drawn on it" || no "…and is drawn on it" "not drawn"
rail=$(body "$H/f/$MFILM?as=$OWNER")
[ "$(echo "$rail" | grep -o ">Camera Spec Sheet<" | wc -l | tr -d ' ')" = 1 ] \
  && ok "…once, not twice" || no "…once, not twice" "$(echo "$rail" | grep -o '>Camera Spec Sheet<' | wc -l | tr -d ' ') rows"

# **A page that would be written and never drawn is refused.** `recordPage`
# draws a tree on the bible and the spec sheet and nowhere else — People is a
# crew list and Documents a pinned list — so a page folded onto either would
# report success and show nothing, which is the worst way to fail.
got=$(said "$(tell '{"jsonrpc":"2.0","id":41,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"People","markdown":"Ellis is the gaffer."}}}')")
echo "$got" | grep -q "set_front" && ok "a page that belongs on a list is sent to the tool that keeps it" \
  || no "a page that belongs on a list is sent to the tool that keeps it" "$got"

# A picture stored for a page is drawn on it and stays off the Documents list.
got=$(said "$(tell '{"jsonrpc":"2.0","id":37,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"A frame","filename":"frame.png","base64":"aGVsbG8gcGljdHVyZQ==","kind":"picture"}}}')")
PIC=$(printf '%s' "$got" | sed -n 's/.*!\[caption\](\([0-9a-f]*\.[a-z]*\)).*/\1/p')
[ -n "$PIC" ] && ok "a picture for a page is stored and its name handed back" \
  || no "a picture for a page is stored and its name handed back" "$got"
# **Built in a variable first.** Written inline as `$(said "$(tell "{\"a\":1}")")`
# bash eats the braces out of the escaped JSON and the worker answers "that is
# not JSON" — which reads exactly like the tool refusing the picture.
ask=$(printf '{"jsonrpc":"2.0","id":38,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Lighting Plan","markdown":"![The alley](%s)"}}}' "$PIC")
drew=$(said "$(tell "$ask")")
echo "$(body "$H/f/$MFILM/lighting-plan?as=$OWNER")" | grep -q "pic/$PIC" \
  && ok "…and drawn on the page from the film's own store" \
  || no "…and drawn on the page from the film's own store" "[$PIC] $drew"
echo "$(body "$H/f/$MFILM/documents?as=$OWNER")" | grep -q "$PIC" \
  && no "…without being listed under Documents" "it is listed" \
  || ok "…without being listed under Documents"

# A picture sent as a link is fetched by the hub at full size (Ref 1442), so an
# agent never has to write the bytes out. A private or dead address is refused.
got=$(said "$(tell '{"jsonrpc":"2.0","id":39,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"Fetched","url":"https://www.w3.org/Icons/w3c_home.png","kind":"picture"}}}')")
echo "$got" | grep -q 'fetched\|Fetched and stored' && ok "a picture sent as a link is fetched and its name handed back" \
  || no "a picture sent as a link is fetched and its name handed back" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":39,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"Nope","url":"https://example.invalid/x.png","kind":"picture"}}}')")
echo "$got" | grep -q "Could not fetch" && ok "…and an address that gives no picture is refused" \
  || no "…and an address that gives no picture is refused" "$got"

# **Several pictures on one line are a row.** A visual bible argues by putting
# references side by side; Markdown has no columns, and a reader that could only
# stack them turned every comparison he had made into a column of unrelated
# stills. Notion's reader has carried his columns from the start — this is the
# same shape said in Markdown.
ask=$(printf '{"jsonrpc":"2.0","id":40,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Lighting Plan","markdown":"![](%s) ![](%s) ![](%s)"}}}' "$PIC" "$PIC" "$PIC")
drew=$(said "$(tell "$ask")")
row=$(body "$H/f/$MFILM/lighting-plan?as=$OWNER")
echo "$row" | grep -q 'class="ncols"' \
  && ok "pictures on one line are drawn side by side" \
  || no "pictures on one line are drawn side by side" "$drew"
[ "$(echo "$row" | grep -o 'class="ncol"' | wc -l | tr -d ' ')" = 3 ] \
  && ok "…one column each" || no "…one column each" "$(echo "$row" | grep -c 'class="ncol"') columns"

# **An agent writing the Visual Bible writes it onto the film's own page.**
# `FOLDS` sends `Visual Bible` to `bible`; what was missing was the other half —
# the page drawing both. `recordBody` dispatched on "is there a section with
# this slug", so the moment an agent wrote one the film's own paragraphs were
# thrown away without a word.
got=$(said "$(tell '{"jsonrpc":"2.0","id":42,"method":"tools/call","params":{"name":"set_front","arguments":{"look":"Controlled to freedom."}}}')")
ask='{"jsonrpc":"2.0","id":43,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Visual Bible","markdown":"## Dogma\n\n- Hard lines belong to the mansion"}}}'
got=$(said "$(tell "$ask")")
echo "$got" | grep -q "/bible" \
  && ok "an agent's Visual Bible lands on the film's own page" \
  || no "an agent's Visual Bible lands on the film's own page" "$got"
bib=$(body "$H/f/$MFILM/bible?as=$OWNER")
echo "$bib" | grep -q "Hard lines belong to the mansion" \
  && ok "…and what it wrote is on it" || no "…and what it wrote is on it" "not drawn"
! echo "$bib" | grep -q "Controlled to freedom" && body "$H/f/$MFILM?as=$OWNER" | grep -q "Controlled to freedom" \
  && ok "…while the film's own paragraphs stay on its front page" \
  || no "…while the film's own paragraphs stay on its front page" "the prose is on the bible, or gone"
[ "$(body "$H/f/$MFILM?as=$OWNER" | grep -o ">Visual Bible<" | wc -l | tr -d ' ')" = 1 ] \
  && ok "…and the rail still names it once" || no "…and the rail still names it once" "twice"

# Taking it off takes the row and the page together.
got=$(said "$(tell '{"jsonrpc":"2.0","id":39,"method":"tools/call","params":{"name":"remove_page","arguments":{"slug":"lighting-plan"}}}')")
echo "$got" | grep -q "is off" && ok "an agent can take its own page away" || no "an agent can take its own page away" "$got"
[ "$(code "$H/f/$MFILM/lighting-plan?as=$OWNER")" = 404 ] \
  && ok "…and the address stops answering" || no "…and the address stops answering" "still answers"

# ---- a page can be read back, not only written ------------------------------
#
# **The half that makes the film's page a source of truth.** His decision,
# 2026-09-04: the portal page holds a bible's words, pictures and order, and the
# deck editor on his Mac renders the PDF from the same thing. That only works if
# a page can be read — until now this store was write-only, so an agent asked to
# revise a bible could not see what it was revising.
# **`printf` turns `\n` into a real newline, and a real newline inside a JSON
# string is not JSON.** The worker answered "That is not JSON", the page was
# never made, and the five checks below it all failed saying the page did not
# exist — which reads as a fault in the tool under test rather than in the way
# the question was asked. `%%s` for the value, `\\n` for the escape.
ask=$(printf '{"jsonrpc":"2.0","id":50,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Look Notes","markdown":"# Night\\n\\nSodium only, and a [condor](https://example.com/c).\\n\\n- Two 18Ks\\n  - half CTB\\n- Nothing on faces\\n\\n> Let it go black.\\n\\n![One](%s) ![Two](%s)"}}}' "$PIC" "$PIC")
said "$(tell "$ask")" >/dev/null
got=$(said "$(tell '{"jsonrpc":"2.0","id":51,"method":"tools/call","params":{"name":"page","arguments":{"slug":"look-notes"}}}')")
echo "$got" | grep -q '"markdown"' && ok "a page can be read back as the Markdown that made it" \
  || no "a page can be read back as the Markdown that made it" "$got"
echo "$got" | grep -q "Sodium only" && ok "…with its words" || no "…with its words" "no words"
echo "$got" | grep -q "half CTB" && ok "…its nesting" || no "…its nesting" "no nesting"
echo "$got" | grep -q "$PIC" && ok "…and its pictures" || no "…and its pictures" "no picture"
echo "$got" | grep -q '"written_by": "an agent' \
  && ok "…and it says which road the page came in on" \
  || no "…and it says which road the page came in on" "$got"

# **The round trip is the whole claim.** Write what was read back, and the page
# must still say the same thing — otherwise the deck editor rendering a PDF from
# it and an agent revising it would drift apart on every pass.
python3 - "$got" > /tmp/hubcheck-round.json <<'PYEOF'
import json, sys
md = json.loads(sys.argv[1])["markdown"]
print(json.dumps({"jsonrpc":"2.0","id":52,"method":"tools/call","params":{
  "name":"set_page","arguments":{"name":"Look Notes","markdown":md}}}))
PYEOF
said "$(tell "$(cat /tmp/hubcheck-round.json)")" >/dev/null
rm -f /tmp/hubcheck-round.json
again=$(said "$(tell '{"jsonrpc":"2.0","id":53,"method":"tools/call","params":{"name":"page","arguments":{"slug":"look-notes"}}}')")
[ "$(printf '%s' "$got" | python3 -c 'import sys,json;print(json.load(sys.stdin)["markdown"])')" = \
  "$(printf '%s' "$again" | python3 -c 'import sys,json;print(json.load(sys.stdin)["markdown"])')" ] \
  && ok "writing back what was read leaves the page unchanged" \
  || no "writing back what was read leaves the page unchanged" "it drifted"
echo "$(body "$H/f/$MFILM/look-notes?as=$OWNER")" | grep -q "Let it go black" \
  && ok "…and the page still draws" || no "…and the page still draws" "not drawn"

# A page that came from Notion can be read here too — reading is not changing.
got=$(said "$(tell '{"jsonrpc":"2.0","id":54,"method":"tools/call","params":{"name":"page","arguments":{"slug":"prep-notes"}}}')")
echo "$got" | grep -q "Truck loads at six" && ok "a Notion page can be read, though not written" \
  || no "a Notion page can be read, though not written" "$got"
echo "$got" | grep -q "change it in Notion, which is where it comes from now" \
  && ok "…and says both roads: take it over here, or write it there" \
  || no "…and says both roads: take it over here, or write it there" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":55,"method":"tools/call","params":{"name":"page","arguments":{"slug":"nothing-here"}}}')")
echo "$got" | grep -qi "no page at" && ok "a page that does not exist is refused" \
  || no "a page that does not exist is refused" "$got"

# ---- a page published as a finished document ---------------------------------
#
# **One deck design, two media.** His decision, 2026-09-05: the same deck that
# prints the PDF also makes a web page, and `deck-builder/tools/publish.py` puts
# it beside the film. When one is there the portal draws it instead of styling
# the tree itself — same address, same rail, the document's own design inside.
cat > /tmp/hubcheck-made.html <<'HTML'
<style>.deckweb h2{letter-spacing:.2em}</style>
<div class="deckweb"><h2>Night Exteriors</h2><p>Sodium only.</p>
<script>window.stolen=document.cookie</script>
<img src="pic/aa.jpg" onerror="alert(1)"></div>
HTML
put "p/$MFILM/pages/look-notes.html" /tmp/hubcheck-made.html
rm -f /tmp/hubcheck-made.html
made=$(body "$H/f/$MFILM/look-notes?as=$OWNER")
echo "$made" | grep -q "Night Exteriors" \
  && ok "a published page is drawn instead of the tree" \
  || no "a published page is drawn instead of the tree" "not drawn"
echo "$made" | grep -q "letter-spacing:.2em" \
  && ok "…with its own design" || no "…with its own design" "no style"
echo "$made" | grep -q "Sodium only, and a" \
  && no "…and the tree it replaces is not drawn as well" "both drawn" \
  || ok "…and the tree it replaces is not drawn as well"
# **His own file, and still stripped.** It is markup written elsewhere and
# injected into a signed-in page; the cost of being wrong is somebody's session.
echo "$made" | grep -q "window.stolen" \
  && no "a script in a published page is cut out" "the script survived" \
  || ok "a script in a published page is cut out"
echo "$made" | grep -q "onerror=" \
  && no "…and so is an inline handler" "the handler survived" \
  || ok "…and so is an inline handler"

# A film with nothing published still draws exactly as it did.
echo "$(body "$H/f/$MFILM/prep-notes?as=$OWNER")" | grep -q "Truck loads at six" \
  && ok "a page with no document still draws its tree" \
  || no "a page with no document still draws its tree" "not drawn"

# ---- adding a page, on the film itself --------------------------------------
# His ruling, 2026-09-05: a deck is always a page of a film, so the project is
# decided by where you stood rather than by a field. Until this existed the
# portal could not make a page at all — only Notion and `set_page` could — and
# a deck publishing a new one wrote a file at an address that answered 404.

got=$(body "$H/f/$FILM?as=$OWNER")
echo "$got" | grep -q 'href="[^"]*/add"' \
  && ok "an editor is offered a way to add a page" \
  || no "an editor is offered a way to add a page" "no link on the rail"

got=$(body "$H/f/$FILM?as=$DIRECTOR")
echo "$got" | grep -q 'href="[^"]*/add"' \
  && no "…and a viewer is not" "the link is there" \
  || ok "…and a viewer is not"

[ "$(code "$H/f/$FILM/add?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot open the add-page form" \
  || no "a viewer cannot open the add-page form" "not 403"

[ "$(code "$H/f/$FILM/add?as=$OWNER")" = 200 ] \
  && ok "an editor can open it" || no "an editor can open it" "not 200"

made=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$H/f/$FILM/add?as=$OWNER" \
       --data-urlencode "name=Lighting Plan")
[ "$made" = 303 ] && ok "adding a page sends you to it" || no "adding a page sends you to it" "$made"

[ "$(code "$H/f/$FILM/lighting-plan?as=$OWNER")" = 200 ] \
  && ok "…and its address answers, which is the whole point" \
  || no "…and its address answers, which is the whole point" "not 200"

echo "$(body "$H/f/$FILM?as=$OWNER")" | grep -q "Lighting Plan" \
  && ok "…and it is on the rail" || no "…and it is on the rail" "not listed"

got=$(body -X POST "$H/f/$FILM/add?as=$OWNER" --data-urlencode "name=Lighting Plan")
echo "$got" | grep -q "already a page" \
  && ok "the same name twice is refused, and says so" \
  || no "the same name twice is refused, and says so" "no refusal"

got=$(body -X POST "$H/f/$FILM/add?as=$OWNER" --data-urlencode "name=   ")
echo "$got" | grep -q "Give the page a name" \
  && ok "a nameless page is refused" || no "a nameless page is refused" "no refusal"

# ---- the rail, in the order he dragged it into -------------------------------
# **The director is put back on the film first.** The link checks above take
# everybody off it, so every "…and a viewer does not" between there and here is
# reading a 403 page and passing for the wrong reason. These three below are
# about what a *viewer* is shown, so they need a viewer.
sent=$(printf '{"people":[{"email":"%s","role":"viewer"}],"links":[],"invites":[]}' "$DIRECTOR")
curl -s -o /dev/null -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER"
[ "$(code "$H/f/$FILM?as=$DIRECTOR")" = 200 ] \
  && ok "the director is back on the film, so a viewer means a viewer" \
  || no "the director is back on the film, so a viewer means a viewer" "not 200"

# A POST that says both what came back and why, because a refusal here is a
# sentence the screen shows him and a bare 200 says nothing about which one.
post() { curl -s -w "\n%{http_code}" -X POST "$@"; }

# Ref 870, and his answer of 2026-09-08: *"I like your recommendation here as
# well. Dragging is good."* Until this, his own pages sat on the end of the list
# in the order they happened to arrive and could never be moved, so a crew
# member opening the film read his thinking sorted by accident.
#
# **The dragging itself is a browser behaviour and no check here can see it.**
# What these hold is everything underneath it: who may save an order, what a key
# may be, and — the one that matters — that the order actually comes out of the
# rail afterwards.

got=$(body "$H/f/$FILM?as=$OWNER")
echo "$got" | grep -q 'data-arrange=' \
  && ok "an editor's rail says it can be arranged" \
  || no "an editor's rail says it can be arranged" "no mark on the rail"

echo "$(body "$H/f/$FILM?as=$DIRECTOR")" | grep -q 'data-arrange=' \
  && no "…and a viewer's does not" "the mark is there" \
  || ok "…and a viewer's does not"

[ "$(code -X POST "$H/f/$FILM/order?as=$DIRECTOR" --data-urlencode "group=
people,shotlist")" = 403 ] \
  && ok "a viewer cannot rearrange the film" \
  || no "a viewer cannot rearrange the film" "not 403"

[ "$(code -X POST "$H/f/$FILM/order?as=$OWNER" --data-urlencode "group=Script & Shots
lighting-plan,shotlist")" = 204 ] \
  && ok "an editor can" || no "an editor can" "not 204"

# **The whole point, and the only one worth a check.** Everything above is a
# gate; this is whether the drag did anything.
got=$(body "$H/f/$FILM?as=$OWNER")
first=$(printf '%s' "$got" | grep -bo 'data-key="lighting-plan"' | head -1 | cut -d: -f1)
last=$(printf '%s' "$got" | grep -bo 'data-key="shotlist"' | head -1 | cut -d: -f1)
[ -n "$first" ] && [ -n "$last" ] && [ "$first" -lt "$last" ] \
  && ok "…and the rail comes back in that order" \
  || no "…and the rail comes back in that order" "lighting-plan=$first shotlist=$last"

# An order is the film's, not the reader's: a director sees what he arranged.
got=$(body "$H/f/$FILM?as=$DIRECTOR")
first=$(printf '%s' "$got" | grep -bo 'data-key="lighting-plan"' | head -1 | cut -d: -f1)
last=$(printf '%s' "$got" | grep -bo 'data-key="shotlist"' | head -1 | cut -d: -f1)
[ -n "$first" ] && [ -n "$last" ] && [ "$first" -lt "$last" ] \
  && ok "…and a viewer reads it in his order too" \
  || no "…and a viewer reads it in his order too" "lighting-plan=$first shotlist=$last"

# **A row he has never dragged is not lost**, which is what lets a page added
# this morning appear at all without the whole rail being arranged first.
echo "$got" | grep -q 'data-key="documents"' \
  && ok "…and a row not named in the order is still drawn" \
  || no "…and a row not named in the order is still drawn" "dropped"

# `tidy` in front.js is the gate on what a key may be, so rubbish is dropped
# rather than refused — the rest of the order still lands.
[ "$(code -X POST "$H/f/$FILM/order?as=$OWNER" --data-urlencode "group=
people,NOT A KEY,shotlist")" = 204 ] \
  && ok "a key that is not an address is dropped, not fatal" \
  || no "a key that is not an address is dropped, not fatal" "not 204"
echo "$(body "$H/f/$FILM?as=$OWNER")" | grep -q 'data-key="shotlist"' \
  && ok "…and the rail still draws" || no "…and the rail still draws" "rail is gone"

[ "$(code "$H/f/$FILM/order?as=$OWNER")" = 404 ] \
  && ok "order is a save, not a page" || no "order is a save, not a page" "it drew something"

# ---- the sidebar's headings are the Library's categories ---------------------
# His ruling, 2026-10-11: the sidebar's headings and the Library's categories
# were two systems naming the same things, and they are one now. A heading is
# a category: made, renamed, removed and put in order on the Categories page
# (the old Headings page), filled by dragging pages under it on the rail.

[ "$(code "$H/f/$FILM/groups?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot name the categories" || no "a viewer cannot name the categories" "not 403"
[ "$(code "$H/f/$FILM/groups?as=$OWNER")" = 200 ] \
  && ok "an editor can" || no "an editor can" "not 200"

made=$(code -X POST "$H/f/$FILM/groups?as=$OWNER" --data-urlencode "new=Logistics")
[ "$made" = 303 ] && ok "a category can be made" || no "a category can be made" "$made"

got=$(body -X POST "$H/f/$FILM/groups?as=$OWNER" --data-urlencode "new=Logistics")
echo "$got" | grep -q "already a Logistics category" \
  && ok "…and the same one twice is refused" || no "…and the same one twice is refused" "no refusal"
body -X POST "$H/f/$FILM/groups?as=$OWNER" --data-urlencode "new=Creative" | grep -q "already a Creative category" \
  && ok "…and so is the name of one of the four" || no "…and so is the name of one of the four" "no refusal"

# **A category with nothing in it yet still draws, for him.** It is empty
# because he is about to drag something into it, and one that will not appear
# until it has rows is one with nowhere to drop the first row.
echo "$(body "$H/f/$FILM?as=$OWNER")" | grep -q '<div class="grouphead"[^>]*>Logistics</div>' \
  && ok "…and an empty category is there to drag into" \
  || no "…and an empty category is there to drag into" "not drawn"
echo "$(body "$H/f/$FILM?as=$DIRECTOR")" | grep -q '<div class="grouphead"[^>]*>Logistics</div>' \
  && no "…and a viewer is not shown a heading over nothing" "they see it" \
  || ok "…and a viewer is not shown a heading over nothing"

# **Filled by dragging**, which is what the rail posts: a row under a heading
# is filed in that category, and the Library says so.
code -X POST "$H/f/$FILM/order?as=$OWNER" --data-urlencode "group=Logistics
schedule,people" --data-urlencode "group=Creative
bible,boards" --data-urlencode "group=
shotlist" >/dev/null
got=$(body "$H/f/$FILM?as=$OWNER")
lg=$(printf '%s' "$got" | grep -bo '>Logistics<' | head -1 | cut -d: -f1)
lk=$(printf '%s' "$got" | grep -bo '>Creative<' | head -1 | cut -d: -f1)
sched=$(printf '%s' "$got" | grep -bo 'data-key="schedule"' | head -1 | cut -d: -f1)
bible=$(printf '%s' "$got" | grep -bo 'data-key="bible"' | head -1 | cut -d: -f1)
[ -n "$lg" ] && [ "$lg" -lt "$sched" ] && [ "$sched" -lt "$lk" ] && [ "$lk" -lt "$bible" ] \
  && ok "…rows under the headings he put them under, headings in the order he sent" \
  || no "…rows under the headings he put them under, headings in the order he sent" "Logistics=$lg schedule=$sched Creative=$lk bible=$bible"
echo "$(body "$H/f/$FILM?as=$DIRECTOR")" | grep -q '<div class="grouphead"[^>]*>Logistics</div>' \
  && ok "…and a viewer reads it too" || no "…and a viewer reads it too" "no heading for them"

# **Renaming keeps what is under it**, or filing anything would be a thing you
# do once and never dare touch again. The field says which category it was by
# its id (`was`).
code -X POST "$H/f/$FILM/groups?as=$OWNER" --data-urlencode "name=Logistics Plan" --data-urlencode "was=x-logistics" >/dev/null
got=$(body "$H/f/$FILM?as=$OWNER")
echo "$got" | grep -q '<div class="grouphead"[^>]*>Logistics Plan</div>' \
  && ok "renaming a category keeps the heading" || no "renaming a category keeps the heading" "gone"
head=$(printf '%s' "$got" | grep -bo '>Logistics Plan<' | head -1 | cut -d: -f1)
under=$(printf '%s' "$got" | grep -bo 'data-key="schedule"' | head -1 | cut -d: -f1)
[ -n "$head" ] && [ "$head" -lt "$under" ] \
  && ok "…and everything under it" || no "…and everything under it" "Logistics Plan=$head schedule=$under"

# **The Categories page**: a list with a grip, a cross on the ones he added.
got=$(body "$H/f/$FILM/groups?as=$OWNER")
echo "$got" | grep -q 'class="fh-headrow" data-head="Creative"' && echo "$got" | grep -q 'class="fh-grip"' \
  && ok "the Categories page is a list of rows with a grip" \
  || no "the Categories page is a list of rows with a grip" "no row or no grip"
echo "$got" | grep -q 'class="fh-headdrop" type="submit" name="drop" value="x-logistics"' \
  && ok "…a cross on one he added" || no "…a cross on one he added" "no cross"
echo "$got" | grep -q 'name="drop" value="creative"' \
  && no "…and none on the four" "a built in one can be removed" || ok "…and none on the four"
# **Enter in a field must not press a cross.** A form's Enter goes through its
# first submit button; the first one here is a hidden plain one, before any row.
first=$(printf '%s' "$got" | grep -bo 'class="fh-default" type="submit"' | head -1 | cut -d: -f1)
cross=$(printf '%s' "$got" | grep -bo 'class="fh-headdrop"' | head -1 | cut -d: -f1)
[ -n "$first" ] && [ "$first" -lt "$cross" ] \
  && ok "…and Enter in a field does not remove the first category" \
  || no "…and Enter in a field does not remove the first category" "default=$first cross=$cross"
echo "$got" | grep -q 'class="fh-headtpl"' \
  && ok "…and carries the row the script clones for a new category" \
  || no "…and carries the row the script clones for a new category" "no template"

# Sent in the other order, the categories are in the other order, rows with them.
code -X POST "$H/f/$FILM/groups?as=$OWNER" \
  --data-urlencode "name=Logistics Plan" --data-urlencode "was=x-logistics" \
  --data-urlencode "name=Creative" --data-urlencode "was=creative" --data-urlencode "new=" >/dev/null
got=$(body "$H/f/$FILM?as=$OWNER")
lg=$(printf '%s' "$got" | grep -bo '>Logistics Plan<' | head -1 | cut -d: -f1)
lk=$(printf '%s' "$got" | grep -bo '>Creative<' | head -1 | cut -d: -f1)
[ -n "$lg" ] && [ -n "$lk" ] && [ "$lg" -lt "$lk" ] \
  && ok "categories are put in the order they are sent" \
  || no "categories are put in the order they are sent" "Logistics Plan=$lg Creative=$lk"

# Renamed into a name already taken: refused, like a new one would be.
body -X POST "$H/f/$FILM/groups?as=$OWNER" \
  --data-urlencode "name=Logistics Plan" --data-urlencode "was=x-logistics" \
  --data-urlencode "name=logistics plan" --data-urlencode "was=creative" --data-urlencode "new=" \
  | grep -q "already a logistics plan category" \
  && ok "renaming a category into a taken name is refused" \
  || no "renaming a category into a taken name is refused" "two categories, one name"

# **The cross removes, and never destroys.** Its pages go back to where they
# would be filed anyway.
code -X POST "$H/f/$FILM/groups?as=$OWNER" \
  --data-urlencode "name=Logistics Plan" --data-urlencode "was=x-logistics" \
  --data-urlencode "name=Creative" --data-urlencode "was=creative" --data-urlencode "drop=x-logistics" --data-urlencode "new=" >/dev/null
got=$(body "$H/f/$FILM?as=$OWNER")
echo "$got" | grep -q '>Logistics Plan<' \
  && no "the cross removes a category" "still there" || ok "the cross removes a category"
echo "$got" | grep -q 'data-key="schedule"' && echo "$got" | grep -q '>Creative<' \
  && ok "…and its pages stay on the rail, the other categories untouched" \
  || no "…and its pages stay on the rail, the other categories untouched" "DESTROYED"

# **The order does not snap back.** Two copies of it lived on the page: the
# app's (`HUB.rail.groups`, drawn again on every paint) and the pages `deep.js`
# had fetched ahead, every one carrying the rail as it was before the drag.
grep -q 'window.HUB.rail.order = orderAfter(' "$HERE/public/arrange.js" && grep -q 'window.HUB.rail.filed = filed' "$HERE/public/arrange.js" \
  && ok "a drag brings the app's own copy of the order up to date" \
  || no "a drag brings the app's own copy of the order up to date" "HUB.rail.order and filed untouched"
grep -q '"arranging"' "$HERE/public/arrange.js" && grep -q '"arranged"' "$HERE/public/arrange.js" \
  && grep -q '"arranging"' "$HERE/public/deep.js" && grep -q 'have.at >= arrangedAt' "$HERE/public/deep.js" \
  && ok "…and tells deep.js, which treats every page fetched before it as stale" \
  || no "…and tells deep.js, which treats every page fetched before it as stale" "not wired"

# ---- where a page's words come from, set on the page ------------------------
# Ref 871. Every page has carried a source since 2026-09-08 and nothing could
# set it — and the only way to snapshot a Notion page was to have an agent copy
# it, which locked Notion out for good. His decision: the source decides who
# wins, **and it is changeable both ways**.

# **`overheads` is Notion's own** — it went on the card with no `by`, the way a
# Hub-ticked Project Docs row arrives — so it is the page where the choice is
# real. `lighting-plan` was made on the portal and is the page where it is not.
got=$(body "$H/f/$FILM/overheads?as=$OWNER")
echo "$got" | grep -q 'value="notion-once"' \
  && ok "an editor is offered the source of a page Notion names" \
  || no "an editor is offered the source of a page Notion names" "no control"

echo "$(body "$H/f/$FILM/overheads?as=$DIRECTOR")" | grep -q 'name="source"' \
  && no "…and a viewer is not" "the control is there" || ok "…and a viewer is not"

[ "$(code -X POST "$H/f/$FILM/overheads?as=$DIRECTOR" --data-urlencode "source=here")" = 403 ] \
  && ok "a viewer cannot change it" || no "a viewer cannot change it" "not 403"

[ "$(code -X POST "$H/f/$FILM/overheads?as=$OWNER" --data-urlencode "source=nonsense")" = 400 ] \
  && ok "a source that does not exist is refused" \
  || no "a source that does not exist is refused" "not 400"

[ "$(code -X POST "$H/f/$FILM/overheads?as=$OWNER" --data-urlencode "source=notion-once")" = 303 ] \
  && ok "an editor can take a snapshot of a Notion page" \
  || no "an editor can take a snapshot of a Notion page" "not 303"
echo "$(body "$H/f/$FILM/overheads?as=$OWNER")" | grep -q "Copied from Notion once" \
  && ok "…and the page says so" || no "…and the page says so" "not said"

# **The end of the one-way door**, which is the whole of Ref 871.
[ "$(code -X POST "$H/f/$FILM/overheads?as=$OWNER" --data-urlencode "source=notion")" = 303 ] \
  && ok "…and he can hand it straight back to Notion" \
  || no "…and he can hand it straight back to Notion" "not 303"
echo "$(body "$H/f/$FILM/overheads?as=$OWNER")" | grep -q "Live from Notion" \
  && ok "…and it says that too" || no "…and it says that too" "not said"

# ---- the Notion column that makes a page -------------------------------------
# His question, 2026-09-08: "I notice you added a column called Section to my
# Project Docs database, but section relates to a page or a section?" It makes a
# page. Every word he reads says page; that column is the last place the old
# word survives. So both names answer, and he can rename it whenever he likes.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
page = {'properties': {'Page': {'type': 'select', 'select': {'name': 'Lighting Plan'}}}}
old  = {'properties': {'Section': {'type': 'select', 'select': {'name': 'Lighting'}}}}
sys.exit(0 if refresh.page_column(page) == 'Lighting Plan'
         and refresh.page_column(old) == 'Lighting'
         and refresh.page_column({'properties': {}}) == '' else 1)" 2>/dev/null \
  && ok "the Notion column may be called Page or Section" \
  || no "the Notion column may be called Page or Section" "one of them is not read"

# **And a name that would twin one of the film's own screens is refused.**
# `Locations` and `Schedule` sit in that dropdown today; either would put a
# second row of that name on the rail, one into the program and one to a page of
# words, with nothing to tell them apart.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
sys.exit(0 if refresh.section_slug('Locations') in refresh.FILM_SCREENS
         and refresh.section_slug('Schedule') in refresh.FILM_SCREENS
         and refresh.section_slug('Lighting') not in refresh.FILM_SCREENS
         and refresh.section_slug('Visual Bible') == 'bible' else 1)" 2>/dev/null \
  && ok "…and a page named after one of the film's own screens is not one" \
  || no "…and a page named after one of the film's own screens is not one" "it would twin a screen"

# ---- taking a page off the film ---------------------------------------------
# His question, 2026-09-08: "how do i delete a page?" He could not, from the
# site — Add was built and its other half was not, so everything he made on the
# portal was permanent unless he asked somebody.

# A page made for this, so nothing later in the file loses the ground under it.
code -X POST "$H/f/$FILM/add?as=$OWNER" --data-urlencode "type=page" --data-urlencode "name=Scratch Page" >/dev/null
got=$(body "$H/f/$FILM/scratch-page?as=$OWNER")
echo "$got" | grep -q 'name="remove"' \
  && ok "an editor is offered a way to take a page off" \
  || no "an editor is offered a way to take a page off" "no control"
echo "$got" | grep -q "Deletes the page" \
  && ok "…and is told what goes with it" || no "…and is told what goes with it" "silent"
echo "$(body "$H/f/$FILM/scratch-page?as=$DIRECTOR")" | grep -q 'name="remove"' \
  && no "…and a viewer is not" "the control is there" || ok "…and a viewer is not"

made=$(code -X POST "$H/f/$FILM/scratch-page?as=$DIRECTOR" --data-urlencode "remove=scratch-page")
[ "$made" = 403 ] && ok "…and cannot do it either" || no "…and cannot do it either" "$made"

# **A page Notion names is refused**, because it would come straight back at the
# next refresh — worse than saying no.
got=$(body "$H/f/$FILM/overheads?as=$OWNER")
echo "$got" | grep -q "Rename in Notion" \
  && ok "a page Notion names says where it really goes" \
  || no "a page Notion names says where it really goes" "no line"
made=$(code -X POST "$H/f/$FILM/overheads?as=$OWNER" --data-urlencode "remove=overheads")
[ "$made" = 409 ] && ok "…and removing it here is refused" || no "…and removing it here is refused" "$made"
[ "$(code "$H/f/$FILM/overheads?as=$OWNER")" = 200 ] \
  && ok "…so it is still there" || no "…so it is still there" "it went anyway"

made=$(code -X POST "$H/f/$FILM/scratch-page?as=$OWNER" --data-urlencode "remove=scratch-page")
[ "$made" = 303 ] && ok "an editor can take his own page off" || no "an editor can take his own page off" "$made"
[ "$(code "$H/f/$FILM/scratch-page?as=$OWNER")" = 404 ] \
  && ok "…and its address stops answering" || no "…and its address stops answering" "still 200"
echo "$(body "$H/f/$FILM?as=$OWNER")" | grep -q 'data-key="scratch-page"' \
  && no "…and it is off the sidebar" "still listed" || ok "…and it is off the sidebar"
# **And nothing else went with it.**
[ "$(code "$H/f/$FILM/lighting-plan?as=$OWNER")" = 200 ] \
  && ok "…and the pages beside it are untouched" || no "…and the pages beside it are untouched" "not 200"

# ---- unpinning a document ----------------------------------------------------
# Archive took Unpin's place on a document's row on 2026-10-13 (a link is a
# page like any other); the old unpin post below still answers.
got=$(body "$H/f/$FILM/documents?as=$OWNER")
echo "$got" | grep -q 'name="archive" value="doc:' \
  && ok "his own documents can be unpinned" || no "his own documents can be unpinned" "no control"
echo "$(body "$H/f/$FILM/documents?as=$DIRECTOR")" | grep -q 'name="archive" value="doc:' \
  && no "…and a viewer cannot" "the control is there" || ok "…and a viewer cannot"

code -X POST "$H/f/$FILM/add?as=$OWNER" -F "type=link" -F "name=Scratch Link" \
  -F "url=https://example.com/scratch" >/dev/null
echo "$(body "$H/f/$FILM/documents?as=$OWNER")" | grep -q "Scratch Link" \
  && ok "…a link he pinned is listed" || no "…a link he pinned is listed" "not listed"
made=$(code -X POST "$H/f/$FILM/documents?as=$OWNER" --data-urlencode "unpin=Scratch Link")
[ "$made" = 303 ] && ok "unpinning one comes back to the list" || no "unpinning one comes back to the list" "$made"
echo "$(body "$H/f/$FILM/documents?as=$OWNER")" | grep -q "Scratch Link" \
  && no "…and it is gone from it" "still listed" || ok "…and it is gone from it"

# **A document Notion pinned is Notion's**, and unpinning it here would put it
# back at the next refresh.
echo "$(body "$H/f/$FILM/documents?as=$OWNER")" | grep -q "A note" \
  && ok "…and Notion's own are untouched" || no "…and Notion's own are untouched" "it went too"

# ---- and the two Notion sources are not offered where they would do nothing --
# His report, 2026-09-08: "live from notion and copied from notion still dont do
# anything." On a page made on the portal there is no Hub-ticked Project Docs
# row behind it, so setting either changed a word and waited for a refresh that
# would never find anything.
got=$(body "$H/f/$FILM/lighting-plan?as=$OWNER")
echo "$got" | grep -q 'value="notion"' \
  && no "a page Notion does not name is not offered Notion" "it is still offered" \
  || ok "a page Notion does not name is not offered Notion"
echo "$got" | grep -q "Not linked to Notion" \
  && ok "…and says so, and what to do about it in Notion" \
  || no "…and says so, and what to do about it in Notion" "silent"
echo "$got" | grep -q "Lighting Plan" \
  && ok "…naming the Section he would have to set" || no "…naming the Section he would have to set" "no name"

made=$(code -X POST "$H/f/$FILM/lighting-plan?as=$OWNER" --data-urlencode "source=notion")
[ "$made" = 409 ] && ok "…and asking for it anyway is refused, not stored" \
  || no "…and asking for it anyway is refused, not stored" "$made"
echo "$(body "$H/f/$FILM/lighting-plan?as=$OWNER")" | grep -q "Written here" \
  && ok "…so the page still says what is true of it" \
  || no "…so the page still says what is true of it" "it took the wrong source"

# **The half underneath**: a refresh has to read the source rather than ask who
# wrote last. `by: "mcp"` used to mean Notion could never feed the page again.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
kept = [{'slug': 'lighting-plan', 'name': 'Lighting Plan'}]
already = [{'slug': 'lighting-plan', 'name': 'Lighting Plan', 'by': 'mcp', 'source': 'notion'}]
out = refresh.both_roads(already, kept)
sys.exit(0 if len(out) == 1 and out[0].get('source') == 'notion' else 1)" 2>/dev/null \
  && ok "a page handed back to Notion is fed by Notion again" \
  || no "a page handed back to Notion is fed by Notion again" "still locked out"

python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
sys.exit(0 if refresh.fed_by_notion({'slug': 'x'})
         and not refresh.fed_by_notion({'slug': 'x', 'source': 'notion-once'})
         and not refresh.fed_by_notion({'slug': 'x', 'by': 'mcp'}) else 1)" 2>/dev/null \
  && ok "…and a snapshot is left alone by the next refresh" \
  || no "…and a snapshot is left alone by the next refresh" "it would be overwritten"

# **A snapshot's row survives a Notion that no longer names it**, or taking one
# would quietly delete the page a fortnight later.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
already = [{'slug': 'overheads', 'name': 'Overheads', 'source': 'notion-once'}]
out = refresh.both_roads(already, [])
sys.exit(0 if [s['slug'] for s in out] == ['overheads'] else 1)" 2>/dev/null \
  && ok "…and Notion dropping its row does not delete the snapshot" \
  || no "…and Notion dropping its row does not delete the snapshot" "destroyed"

# ---- one Add button ----------------------------------------------------------
# Ref 872, his answer: *"Yes, I think Plan B is the way to go."* The type is
# asked first and decides what is asked next.

got=$(body "$H/f/$FILM/add?as=$OWNER")
echo "$got" | grep -q 'name="type"' && ok "the Add screen asks what kind of thing it is" \
  || no "the Add screen asks what kind of thing it is" "no type"
echo "$got" | grep -q 'class="fh-addr' && ok "…and shows the address it will make" \
  || no "…and shows the address it will make" "no address line"

# **Add no longer asks the source, and that is the fix for his report.** Two of
# the three answers need a Notion page to be fed by or copied from, and this
# worker has no Notion token and cannot have one — so all three made the same
# empty page. A page born here is written here, and the box below writes it.
echo "$got" | grep -q 'name="source"' \
  && no "…and does not ask a question it cannot honour" "the source is still asked" \
  || ok "…and does not ask a question it cannot honour"

out=$(post "$H/f/$FILM/add?as=$OWNER" \
      --data-urlencode "type=page" --data-urlencode "name=Safety Briefing")
made=${out##*$'\n'}
[ "$made" = 303 ] && ok "a written page is born written here" \
  || no "a written page is born written here" "$made — $(printf '%s' "$out" | grep -o 'class="warn">[^<]*' | head -1)"
echo "$(body "$H/f/$FILM/safety-briefing?as=$OWNER")" | grep -q "Written here" \
  && ok "…and says so from the start" || no "…and says so from the start" "not said"

# ---- and a written page can actually be written ------------------------------
# His report, 2026-09-08: "All of the options under the written page add doesn't
# work at all. They all lead to empty or broken URLs and have no function." The
# address answered and the row was on the rail; what was missing was any way for
# him to put words on it. Only `set_page` could, and that is an agent's door.

got=$(body "$H/f/$FILM/safety-briefing?as=$OWNER")
echo "$got" | grep -q 'class="seeform writebox"' \
  && ok "an editor gets a box to write the page in" \
  || no "an editor gets a box to write the page in" "no box"
echo "$got" | grep -q 'class="empty">Empty<' \
  && no "…and no notice telling him it is empty" "the notice is still there" \
  || ok "…and no notice telling him it is empty"

echo "$(body "$H/f/$FILM/safety-briefing?as=$DIRECTOR")" | grep -q 'class="seeform writebox"' \
  && no "…and a viewer does not" "the box is there" || ok "…and a viewer does not"

made=$(code -X POST "$H/f/$FILM/safety-briefing?as=$DIRECTOR" --data-urlencode "markdown=Mine now")
[ "$made" = 403 ] && ok "…and cannot write it either" || no "…and cannot write it either" "$made"

made=$(code -X POST "$H/f/$FILM/safety-briefing?as=$OWNER" \
       --data-urlencode "markdown=## Day one

Rig the 12K before call.

- Genny at the back gate")
[ "$made" = 303 ] && ok "writing it saves and comes back to the page" \
  || no "writing it saves and comes back to the page" "$made"

got=$(body "$H/f/$FILM/safety-briefing?as=$OWNER")
echo "$got" | grep -q "Rig the 12K before call" \
  && ok "…and the words are on the page" || no "…and the words are on the page" "not drawn"
echo "$got" | grep -q "Genny at the back gate" \
  && ok "…lists and all" || no "…lists and all" "the list is gone"
# **The box comes back holding what is there**, or opening it and pressing Save
# would wipe the page. `markdownFrom` and `pageFrom` round-trip.
echo "$got" | grep -q "## Day one" \
  && ok "…and the box holds it back, so a second edit does not wipe it" \
  || no "…and the box holds it back, so a second edit does not wipe it" "the box came back empty"
echo "$(body "$H/f/$FILM/safety-briefing?as=$DIRECTOR")" | grep -q "Rig the 12K before call" \
  && ok "…and a viewer reads it" || no "…and a viewer reads it" "not drawn for them"

# **An empty box never wipes a page** — report, never invent, and never destroy.
made=$(code -X POST "$H/f/$FILM/safety-briefing?as=$OWNER" --data-urlencode "markdown=   ")
[ "$made" = 303 ] && ok "an empty box is refused, not obeyed" || no "an empty box is refused, not obeyed" "$made"
echo "$(body "$H/f/$FILM/safety-briefing?as=$OWNER")" | grep -q "Rig the 12K before call" \
  && ok "…and the page still has its words" || no "…and the page still has its words" "WIPED"

# **Writing a Notion-fed page here takes it over**, exactly as `set_page` does —
# otherwise his words are replaced at the next refresh with nothing said.
made=$(code -X POST "$H/f/$FILM/lighting-plan?as=$OWNER" --data-urlencode "markdown=Mine now.")
[ "$made" = 303 ] && ok "he can write over a page Notion was feeding" \
  || no "he can write over a page Notion was feeding" "$made"
echo "$(body "$H/f/$FILM/lighting-plan?as=$OWNER")" | grep -q "Written here" \
  && ok "…and it says Notion has let go of it" \
  || no "…and it says Notion has let go of it" "still claims to be live"

out=$(post "$H/f/$FILM/add?as=$OWNER" --data-urlencode "type=deck" --data-urlencode "name=Teaser")
made=${out##*$'\n'}
[ "$made" = 303 ] && ok "a deck can be given an address to publish into" \
  || no "a deck can be given an address to publish into" "$made — $(printf '%s' "$out" | grep -o 'class="warn">[^<]*' | head -1)"
echo "$(body "$H/f/$FILM?as=$OWNER")" | grep -q 'data-key="teaser"[^>]*>.*syncico' \
  && no "…and the rail marks it only if it syncs from a document" "a deck carries a sync mark" \
  || ok "…and the rail marks it only if it syncs from a document"
echo "$(body "$H/f/$FILM/teaser?as=$OWNER")" | grep -q 'name="source"' \
  && no "…and its source is not his to change" "the control is there" \
  || ok "…and its source is not his to change"

got=$(body -X POST "$H/f/$FILM/add?as=$OWNER" -F "type=file" -F "name=Call Sheet")
echo "$got" | grep -q "Choose a file" \
  && ok "a file with no file is refused, and says so" \
  || no "a file with no file is refused, and says so" "no refusal"

printf 'a call sheet' > /tmp/hubcheck-call.txt
out=$(post "$H/f/$FILM/add?as=$OWNER" -F "type=file" -F "name=Call Sheet" \
      -F "file=@/tmp/hubcheck-call.txt")
made=${out##*$'\n'}
[ "$made" = 303 ] && ok "a file can be put on a film from the browser" \
  || no "a file can be put on a film from the browser" "$made — $(printf '%s' "$out" | grep -o 'class="warn">[^<]*' | head -1)"
echo "$(body "$H/f/$FILM/documents?as=$OWNER")" | grep -q "Call Sheet" \
  && ok "…and it is pinned under Documents" || no "…and it is pinned under Documents" "not listed"
rm -f /tmp/hubcheck-call.txt

# **A link to anything at all** — his instruction, 2026-09-08: *"I should just
# be able to add links to not just Notion, but anything I want, for example a
# Google Drive folder or a YouTube video."* Until this, the only way to pin one
# was to tick `Hub` on a Project Docs row, so anything not already written down
# in Notion could not go on a film.
out=$(post "$H/f/$FILM/add?as=$OWNER" -F "type=link" -F "name=Rushes Folder" \
      -F "url=https://drive.google.com/drive/folders/abc")
made=${out##*$'\n'}
[ "$made" = 303 ] && ok "a link to anywhere can be pinned to a film" \
  || no "a link to anywhere can be pinned to a film" "$made — $(printf '%s' "$out" | grep -o 'class="warn">[^<]*' | head -1)"
got=$(body "$H/f/$FILM/documents?as=$OWNER")
echo "$got" | grep -q "Rushes Folder" \
  && ok "…and it is listed under Documents" || no "…and it is listed under Documents" "not listed"
echo "$got" | grep -q "drive.google.com" \
  && ok "…and says where it goes" || no "…and says where it goes" "no host"

out=$(post "$H/f/$FILM/add?as=$OWNER" -F "type=link" -F "name=Bad" -F "url=javascript:alert(1)")
printf '%s' "$out" | grep -q "not a web address" \
  && ok "an address that is not http is refused" \
  || no "an address that is not http is refused" "let through"

# **And a refresh may not take it away**, which is the same fault `both_kinds`
# already existed for: it told his uploads from Notion's links by asking which
# carried a `file`, and a link he pins here carries a url like Notion's do.
python3 -c "
import sys
sys.path.insert(0, '$HERE')
import refresh
already = [{'name': 'Rushes Folder', 'url': 'https://drive.google.com/x', 'source': 'here'},
           {'name': 'A note', 'url': 'https://old'}]
out = refresh.both_kinds(already, [{'name': 'A note', 'url': 'https://new'}])
sys.exit(0 if [d['name'] for d in out] == ['Rushes Folder', 'A note']
         and out[1]['url'] == 'https://new' else 1)" 2>/dev/null \
  && ok "…and the next Notion refresh leaves it alone" \
  || no "…and the next Notion refresh leaves it alone" "swept away"

# ---- a deck publishes a finished document -----------------------------------
got=$(said "$(tell '{"jsonrpc":"2.0","id":70,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Pitch Deck","html":"<div class=\"deckweb\"><h1>Anya</h1></div>"}}}')")
echo "$got" | grep -q "finished document" \
  && ok "a page may arrive already designed" \
  || no "a page may arrive already designed" "$got"

echo "$(body "$H/f/$FILM/pitch-deck?as=$OWNER")" | grep -q "Anya" \
  && ok "…and the portal draws it, with no tree behind it" \
  || no "…and the portal draws it, with no tree behind it" "not drawn"

got=$(said "$(tell '{"jsonrpc":"2.0","id":71,"method":"tools/call","params":{"name":"pages"}}')")
echo "$got" | grep -q "Deck Editor" \
  && ok "…and the record says a deck wrote it" \
  || no "…and the record says a deck wrote it" "$got"

# **The design he said he does not want to lose.** Markdown landing on a deck
# would replace a design tuned by hand with a styled paragraph, and the deck
# folder would never know.
got=$(said "$(tell '{"jsonrpc":"2.0","id":72,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Pitch Deck","markdown":"Plain words that would eat the design."}}}')")
echo "$got" | grep -q "written in Deck Editor" \
  && ok "plain words cannot land on a deck" \
  || no "plain words cannot land on a deck" "$got"

echo "$(body "$H/f/$FILM/pitch-deck?as=$OWNER")" | grep -q "Anya" \
  && ok "…and the design is still there afterwards" \
  || no "…and the design is still there afterwards" "the design was lost"

got=$(said "$(tell '{"jsonrpc":"2.0","id":73,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Nothing At All"}}}')")
echo "$got" | grep -q "finished document" \
  && ok "a page with neither words nor a document is refused" \
  || no "a page with neither words nor a document is refused" "$got"

# ---- an agent can do everything he can ---------------------------------------
# His instruction, 2026-09-08: "any AI using the MCP should be able to do any of
# the things that I can do here: adding pages, choosing the type, etc." Three
# things the portal could do and the MCP could not: pin a link, say where a
# page's words come from, and put the rail in an order.

got=$(said "$(tell '{"jsonrpc":"2.0","id":90,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"Rushes Drive","url":"https://drive.google.com/drive/folders/xyz"}}}')")
echo "$got" | grep -q "Rushes Drive is on .*'s sidebar and in its Library" \
  && ok "an agent can pin a link, not only a file" \
  || no "an agent can pin a link, not only a file" "$got"
echo "$(body "$H/f/$MFILM/documents?as=$OWNER")" | grep -q "Rushes Drive" \
  && ok "…and it is on the Documents page" || no "…and it is on the Documents page" "not listed"

# **Adding one must not disturb the rest**, which is the whole reason this is
# not `set_front` — that one replaces the list.
echo "$(body "$H/f/$MFILM/documents?as=$OWNER")" | grep -q "A note" \
  && ok "…and the documents already there are untouched" \
  || no "…and the documents already there are untouched" "the list was replaced"

got=$(said "$(tell '{"jsonrpc":"2.0","id":91,"method":"tools/call","params":{"name":"add_document","arguments":{"name":"Bad","url":"javascript:alert(1)"}}}')")
echo "$got" | grep -q "http" \
  && ok "…and an address that is not http is refused" \
  || no "…and an address that is not http is refused" "$got"

# **The source, set from here.** `call-notes` was taken over by an agent above,
# so it is `here`; handing it back to Notion is the door Ref 871 opened.
got=$(said "$(tell '{"jsonrpc":"2.0","id":92,"method":"tools/call","params":{"name":"set_source","arguments":{"slug":"call-notes","source":"notion"}}}')")
echo "$got" | grep -q "Live from Notion" \
  && ok "an agent can hand a page back to Notion" \
  || no "an agent can hand a page back to Notion" "$got"
echo "$(body "$H/f/$MFILM/call-notes?as=$OWNER")" | grep -q "Live from Notion" \
  && ok "…and the page says so" || no "…and the page says so" "not said"

got=$(said "$(tell '{"jsonrpc":"2.0","id":93,"method":"tools/call","params":{"name":"set_source","arguments":{"slug":"call-notes","source":"notion-once"}}}')")
echo "$got" | grep -q "Copied from Notion once" \
  && ok "…and take a snapshot of it again, both ways" \
  || no "…and take a snapshot of it again, both ways" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":94,"method":"tools/call","params":{"name":"set_source","arguments":{"slug":"call-notes","source":"whatever"}}}')")
echo "$got" | grep -q "notion-once" \
  && ok "…and a source that does not exist is refused" \
  || no "…and a source that does not exist is refused" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":95,"method":"tools/call","params":{"name":"set_source","arguments":{"slug":"pitch-deck","source":"here"}}}')")
echo "$got" | grep -q "Deck Editor" \
  && ok "…and a deck's words are not reassignable" \
  || no "…and a deck's words are not reassignable" "$got"

# **The rail, arranged by saying rather than by dragging.**
got=$(said "$(tell '{"jsonrpc":"2.0","id":96,"method":"tools/call","params":{"name":"arrange","arguments":{"order":["people","call-notes","shotlist"]}}}')")
echo "$got" | grep -q "people, call-notes, shotlist" \
  && ok "an agent can put the rail in an order" \
  || no "an agent can put the rail in an order" "$got"

# **And under his own headings**, which is the shape the sidebar is really in.
got=$(said "$(tell '{"jsonrpc":"2.0","id":103,"method":"tools/call","params":{"name":"arrange","arguments":{"groups":[{"name":"Look","rows":["bible","boards"]},{"name":"Logistics","rows":["schedule","people"]}]}}}')")
echo "$got" | grep -q "Look: bible, boards" \
  && ok "…and under categories of his own" || no "…and under categories of his own" "$got"
got=$(body "$H/f/$MFILM?as=$OWNER")
echo "$got" | grep -q '<div class="grouphead"[^>]*>Logistics</div>' \
  && ok "…which the sidebar draws" || no "…which the sidebar draws" "no heading"
echo "$got" | grep -q 'data-key="documents"' \
  && ok "…and a row it did not name is still there, unfiled" \
  || no "…and a row it did not name is still there, unfiled" "dropped"

got=$(said "$(tell '{"jsonrpc":"2.0","id":104,"method":"tools/call","params":{"name":"arrange","arguments":{}}}')")
echo "$got" | grep -q "groups" \
  && ok "…and arranging nothing at all is refused, not obeyed" \
  || no "…and arranging nothing at all is refused, not obeyed" "$got"
got=$(body "$H/f/$MFILM?as=$OWNER")
first=$(printf '%s' "$got" | grep -bo 'data-key="schedule"' | head -1 | cut -d: -f1)
last=$(printf '%s' "$got" | grep -bo 'data-key="people"' | head -1 | cut -d: -f1)
[ -n "$first" ] && [ -n "$last" ] && [ "$first" -lt "$last" ] \
  && ok "…and the rail comes back in it" || no "…and the rail comes back in it" "schedule=$first people=$last"

# **A key that is not a row is said out loud**, not dropped in silence — that is
# how an agent thinks it has arranged a rail it has not touched.
got=$(said "$(tell '{"jsonrpc":"2.0","id":97,"method":"tools/call","params":{"name":"arrange","arguments":{"order":["people","NOT A ROW","shotlist"]}}}')")
echo "$got" | grep -qi "dropped" \
  && ok "…and says which of them it could not use" \
  || no "…and says which of them it could not use" "$got"

# **`pages` asks the source, not who wrote last.** Saying "change it in Notion"
# of a page he has snapshotted would send an agent to edit words nobody reads.
# **An address with nothing at it yet**, which is the last thing the Add screen
# could do and this could not — and the slot a deck needs to publish into.
got=$(said "$(tell '{"jsonrpc":"2.0","id":100,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Teaser Deck","type":"deck"}}}')")
echo "$got" | grep -q "publish into" \
  && ok "an agent can make an address for a deck to land on" \
  || no "an agent can make an address for a deck to land on" "$got"
[ "$(code "$H/f/$MFILM/teaser-deck?as=$OWNER")" = 200 ] \
  && ok "…and it answers, which is the whole point of it" \
  || no "…and it answers, which is the whole point of it" "not 200"

# **Still refused with no body and no type**, because that is far more often an
# agent that forgot its Markdown than one that meant an empty page.
got=$(said "$(tell '{"jsonrpc":"2.0","id":101,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Forgot The Words"}}}')")
echo "$got" | grep -q "nothing on that page" \
  && ok "…and a page with no words and no type is still refused" \
  || no "…and a page with no words and no type is still refused" "$got"

# **And it may not be aimed at a page that exists**, or a stray `type` would
# take his bible off Notion, write nothing, and report success.
got=$(said "$(tell '{"jsonrpc":"2.0","id":102,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Teaser Deck","type":"deck"}}}')")
echo "$got" | grep -q "already a page on this project" \
  && ok "…and cannot be pointed at one that already exists" \
  || no "…and cannot be pointed at one that already exists" "$got"

# `overheads` was put on the card as Notion's own — no `by` — so snapshotting
# it is the case that used to read wrong: `pages` said "change it in Notion" of
# a page Notion can no longer reach, sending an agent to edit words nobody will
# ever see again.
said "$(tell '{"jsonrpc":"2.0","id":98,"method":"tools/call","params":{"name":"set_source","arguments":{"slug":"overheads","source":"notion-once"}}}')" >/dev/null
got=$(said "$(tell '{"jsonrpc":"2.0","id":99,"method":"tools/call","params":{"name":"pages"}}')")
echo "$got" | grep -q '"words_from"' \
  && ok "pages says where each page's words come from" \
  || no "pages says where each page's words come from" "$got"
echo "$got" | grep -q "Notion has let go of this one" \
  && ok "…and does not send an agent to Notion for a page it has let go of" \
  || no "…and does not send an agent to Notion for a page it has let go of" "$got"

# ---- a deck's words and order live on the film ------------------------------
# His plan of 2026-09-05: the content goes server-side so Notion AI can work on
# it, while the design stays written for the deck and the arrangement stays his.

got=$(said "$(tell '{"jsonrpc":"2.0","id":80,"method":"tools/call","params":{"name":"deck","arguments":{"slug":"nothing-here"}}}')")
echo "$got" | grep -q "no deck at" \
  && ok "asking for a deck that is not there says so" \
  || no "asking for a deck that is not there says so" "$got"

DECKREC='{"version":1,"name":"Visual Bible","slug":"bible","sections":[{"id":"cover","on":true},{"id":"opening","on":true,"groups":[{"emphasis":"hero","pictures":["a"]},{"emphasis":"normal","pictures":["b","c","d"]}]}],"words":{"cover.title1":"Call Her Back","opening.b1":"A house that swallows her."}}'
printf '%s' "$DECKREC" > "$STATE/deckrec.json"
(cd "$HERE" && $W r2 object put "shotlister-preview/p/$FILM/decks/bible.json" --file "$STATE/deckrec.json" --local --persist-to "$STATE" >/dev/null 2>&1)

got=$(said "$(tell '{"jsonrpc":"2.0","id":81,"method":"tools/call","params":{"name":"deck","arguments":{"slug":"bible"}}}')")
echo "$got" | grep -q "Call Her Back" \
  && ok "a deck reads back its words" || no "a deck reads back its words" "$got"
echo "$got" | grep -q '"emphasis": "hero"' \
  && ok "…and says which group carries the section" \
  || no "…and says which group carries the section" "$got"
echo "$got" | grep -q "not readable or writable here" \
  && ok "…and says the design is not its to change" \
  || no "…and says the design is not its to change" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":82,"method":"tools/call","params":{"name":"set_deck","arguments":{"slug":"bible","words":{"opening.b1":"A house that keeps her small."}}}}')")
echo "$got" | grep -q "1 piece of writing" \
  && ok "an AI may rewrite a deck's words" || no "an AI may rewrite a deck's words" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"deck","arguments":{"slug":"bible"}}}')")
echo "$got" | grep -q "keeps her small" \
  && ok "…and the change is there when it is read back" \
  || no "…and the change is there when it is read back" "$got"

# **A word with no place in the design is a word nobody sees.**
got=$(said "$(tell '{"jsonrpc":"2.0","id":84,"method":"tools/call","params":{"name":"set_deck","arguments":{"slug":"bible","words":{"invented.key9":"nowhere"}}}}')")
echo "$got" | grep -q "no place for" \
  && ok "a key the design has no place for is refused" \
  || no "a key the design has no place for is refused" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":85,"method":"tools/call","params":{"name":"set_deck","arguments":{"slug":"bible","sections":["opening","cover"]}}}')")
echo "$got" | grep -q "order of its sections" \
  && ok "an AI may reorder a deck's sections" || no "an AI may reorder a deck's sections" "$got"

# **Leaving one out would drop it**, which is the destruction the law forbids.
got=$(said "$(tell '{"jsonrpc":"2.0","id":86,"method":"tools/call","params":{"name":"set_deck","arguments":{"slug":"bible","sections":["cover"]}}}')")
echo "$got" | grep -q "is missing" \
  && ok "reordering with a section left out is refused" \
  || no "reordering with a section left out is refused" "$got"

got=$(said "$(tell '{"jsonrpc":"2.0","id":87,"method":"tools/call","params":{"name":"set_deck","arguments":{"slug":"bible"}}}')")
echo "$got" | grep -q "Nothing was sent" \
  && ok "asking to change nothing says so" || no "asking to change nothing says so" "$got"

# ---- the deck editor --------------------------------------------------------
# His rebuild of 2026-09-05: the preview is the interface, so this is not a
# screen beside the deck — it is the deck, with handles.

[ "$(code "$H/f/$FILM/bible/edit?as=$OWNER")" = 200 ] \
  && ok "an editor can open a deck" || no "an editor can open a deck" "not 200"

[ "$(code "$H/f/$FILM/bible/edit?as=$DIRECTOR")" = 403 ] \
  && ok "a viewer cannot" || no "a viewer cannot" "not 403"

[ "$(code "$H/f/$FILM/lighting-plan/edit?as=$OWNER")" = 404 ] \
  && ok "a page that is not a deck has nothing to edit" \
  || no "a page that is not a deck has nothing to edit" "not 404"

got=$(body "$H/f/$FILM/bible/edit?as=$OWNER")
echo "$got" | grep -q 'id="deckdoc"' \
  && ok "the deck travels as its own document" \
  || no "the deck travels as its own document" "no template"
# **The colours in, the behaviour out.** This used to demand that front.css be
# kept out altogether, because it styles a `.frames` and so does his deck design
# — but that collision is answered by the shadow root now, and a deck design
# reads the front of house's own tokens, which front.css hangs on `.fh2` rather
# than on `:root`. Without it the identical design drew pale type in the editor
# and near-black type on the site. What must stay out is the front's *scripts*:
# `look.js` binds a click on every picture, and in here a click means *pick this
# one*.
echo "$got" | grep -q 'front.css' \
  && ok "the editor is given the front of house's colours" \
  || no "the editor is given the front of house's colours" "front.css is not loaded"
echo "$got" | grep -q 'look.js' \
  && no "…but not its behaviour" "look.js is loaded, and it steals every click" \
  || ok "…but not its behaviour"
echo "$got" | grep -q 'deck.js?v=' \
  && ok "the editor's script is stamped, so a new one is not the old one" \
  || no "the editor's script is stamped, so a new one is not the old one" "no stamp"

sent=$(printf '{"words":{"cover.title1":"Rewritten"},"sections":[{"id":"cover","on":true}]}')
saved=$(curl -s -X POST "$H/f/$FILM/bible/edit?as=$OWNER" -H 'content-type: application/json' --data "$sent")
echo "$saved" | grep -q '"saved"' && ok "the editor saves" || no "the editor saves" "$saved"

got=$(said "$(tell '{"jsonrpc":"2.0","id":90,"method":"tools/call","params":{"name":"deck","arguments":{"slug":"bible"}}}')")
echo "$got" | grep -q "Rewritten" \
  && ok "…and what it saved is what the deck reads back" \
  || no "…and what it saved is what the deck reads back" "$got"

# **A save is never a replacement.** Only the arrangement and the words may
# change from that screen; the pictures it may draw on are left alone.
echo "$got" | grep -q '"pictures"' || true
[ "$(code "$H/f/$FILM/bible/edit?as=$DIRECTOR" -X POST -H 'content-type: application/json' --data '{"words":{}}')" = 403 ] \
  && ok "a viewer cannot save either" || no "a viewer cannot save either" "not 403"

# ---- what the editor offers -------------------------------------------------
# **Rewritten 2026-09-06.** These asked for a strip of pills — Emphasis, Group,
# Frame, Showing, an `id="go"` jump list — on his report that the ui *"frankly
# sucks"*. That bar is gone: a rail of sections down the left, the deck in the
# middle in either of its two forms, and an inspector down the right that is
# drawn from the record once something is picked. Only what the *server* sends
# can be checked here; the controls themselves are driven in `decks/checks/`,
# where a real pointer presses every one of them.
got=$(body "$H/f/$FILM/bible/edit?as=$OWNER")
for want in "Sections" "Stills" "Publish"; do
  echo "$got" | grep -q ">$want<" \
    && ok "the editor offers $want" || no "the editor offers $want" "not there"
done
echo "$got" | grep -q 'id="sections"' \
  && ok "the sections are a rail of their own" \
  || no "the sections are a rail of their own" "no rail"
echo "$got" | grep -q 'id="insp"' \
  && ok "…and what is picked has an inspector" \
  || no "…and what is picked has an inspector" "no inspector"
# **Two documents, one per side.** Paper is drawn from the print design now
# rather than embedded as the last PDF, so it carries a template of its own.
echo "$got" | grep -q 'id="paperdoc"' \
  && ok "paper is a document, not a picture of one" \
  || no "paper is a document, not a picture of one" "no paper template"
echo "$got" | grep -q 'data-view="paper"' \
  && ok "…and there is a way to it" \
  || no "…and there is a way to it" "no paper switch"
# The shelf reaches past this deck: the film's own stills, and Notion's.
for want in deck film notion; do
  echo "$got" | grep -q "data-source=\"$want\"" \
    && ok "the stills drawer offers $want" \
    || no "the stills drawer offers $want" "not there"
done
# **A label names the thing.** A section derived from a folder is called
# `overall_approach_b`, which is a folder name and not a name.
echo "$got" | grep -q '>overall_approach' \
  && no "the jump list says names, not folder names" "a raw id is in the list" \
  || ok "the jump list says names, not folder names"

# **Publishing puts the deck on the film's page, as drawn.**
# **No nested quotes.** An escaped quote inside a printf format is the shape of
# Ref 751, and it comes back as "that is not JSON" — which reads exactly like
# the route refusing the payload.
sent=$(printf '{"publish":"<p>drawn on screen</p>"}')
saved=$(curl -s -X POST "$H/f/$FILM/bible/edit?as=$OWNER" -H 'content-type: application/json' --data "$sent")
echo "$saved" | grep -q '"published":true' \
  && ok "the editor publishes what is on the screen" \
  || no "the editor publishes what is on the screen" "$saved"
echo "$(body "$H/f/$FILM/bible?as=$OWNER")" | grep -q "drawn on screen" \
  && ok "…and the film's page draws it" || no "…and the film's page draws it" "not drawn"

# ---- a designed page is sealed, and says how to reach it --------------------
# The fault, live and unnoticed since the published-document feature landed:
# front.css AND hub.css both style a `.frames`, and so did his deck design, so
# every row of a section came out side by side as a sixty-pixel sliver — which
# reads as the page having no pictures at all.
got=$(body "$H/f/$FILM/pitch-deck?as=$OWNER")
echo "$got" | grep -q 'made.js' \
  && ok "a designed page is sealed off from the portal's own CSS" \
  || no "a designed page is sealed off from the portal's own CSS" "made.js not loaded"

# **And a page the portal styles must NOT be sealed** — it wants those rules.
# `made.js` rides on every front-of-house page on purpose since a2fe1ed (the
# seal has to be redone after `deep.js` swaps a page in), so its presence says
# nothing; what must be absent is the sealed box itself.
echo "$(body "$H/f/$FILM/people?as=$OWNER")" | grep -q 'class="madepage"' \
  && no "a page the portal draws itself is left alone" "it is sealed in a madepage box" \
  || ok "a page the portal draws itself is left alone"

echo "$got" | grep -q '/pitch-deck/edit' \
  && ok "an editor is shown the way into the deck editor" \
  || no "an editor is shown the way into the deck editor" "no link"

echo "$(body "$H/f/$FILM/pitch-deck?as=$DIRECTOR")" | grep -q '/pitch-deck/edit' \
  && no "…and a viewer is not" "the link is there" \
  || ok "…and a viewer is not"

# ---- the shelf, and a picture dropped on the editor -------------------------
# A shelf of only what is already in the deck can swap but cannot reach. The
# film's own library is listed off storage, because a picture put there with
# add_document is deliberately not listed under Documents.
got=$(body "$H/f/$FILM/bible/edit?as=$OWNER")
echo "$got" | grep -q '"shelf"' \
  && ok "the editor is handed the film's whole picture library" \
  || no "the editor is handed the film's whole picture library" "no shelf"

# aGVsbG8= is "hello" — not a picture, but enough to prove the road works
sent=$(printf '{"add":{"kind":"jpg","base64":"aGVsbG8="}}')
said=$(body -X POST "$H/f/$FILM/bible/edit?as=$OWNER" -H 'content-type: application/json' --data "$sent")
echo "$said" | grep -q '"added"' \
  && ok "a picture dropped on the editor is stored on the film" \
  || no "a picture dropped on the editor is stored on the film" "$said"

# **Named by its own contents**, so the same still twice makes one copy.
again=$(body -X POST "$H/f/$FILM/bible/edit?as=$OWNER" -H 'content-type: application/json' --data "$sent")
[ "$said" = "$again" ] \
  && ok "…and the same picture twice is the same one file" \
  || no "…and the same picture twice is the same one file" "two names"

bad=$(printf '{"add":{"kind":"exe","base64":"aGVsbG8="}}')
said=$(body -X POST "$H/f/$FILM/bible/edit?as=$OWNER" -H 'content-type: application/json' --data "$bad")
echo "$said" | grep -q 'not a picture' \
  && ok "something that is not a picture is refused" \
  || no "something that is not a picture is refused" "$said"

[ "$(code "$H/f/$FILM/bible/edit?as=$DIRECTOR" -X POST -H 'content-type: application/json' --data "$sent")" = 403 ] \
  && ok "a viewer cannot put pictures on the film this way" \
  || no "a viewer cannot put pictures on the film this way" "not 403"

# ---- the deck editor's own front page ---------------------------------------
# His correction, 2026-09-06: the app should open on a hub of decks, the way the
# old one did, not on the portal's front door with the decks a click or two in.
got=$(body "$H/decks?as=$OWNER")
# **Listed because it has a deck's record**, not because its section wears a
# stamp. His own bible came from Notion and is published to by Deck Editor —
# filtering on the stamp showed him an empty hub with his deck sitting in it.
echo "$got" | grep -q "Visual Bible" \
  && ok "the deck hub lists a deck from a film" \
  || no "the deck hub lists a deck from a film" "not listed"
# **Daybreak, not Call Her Back** — the MCP checks above open that film before
# they make a deck, so that is the film this one belongs to. Asserting the other
# name here would be asserting where an earlier check left the session.
# **That it names a film, not which one.** Both seeded films end up with a
# deck record here, and which appears first is the order the MCP checks above
# happened to leave things in — asserting a name would be testing that.
echo "$got" | grep -q 'class="df">[A-Z]' \
  && ok "…and says which film it belongs to" \
  || no "…and says which film it belongs to" "$(echo "$got" | grep -o 'class=.df.>[^<]*' | head -2)"
echo "$got" | grep -q '/bible/edit' \
  && ok "…and the way in is on the row" || no "…and the way in is on the row" "no edit link"

# **Only pages a deck wrote.** A page from Notion or an agent is not a deck and
# has no editor; listing one would offer a door that opens onto nothing.
echo "$got" | grep -q 'call-notes/edit' \
  && no "a page that is not a deck is not listed as one" "an agent's page is on the hub" \
  || ok "a page that is not a deck is not listed as one"

echo "$(body "$H/decks?as=$STRANGER")" | grep -q "No decks yet" \
  && ok "a stranger sees an empty hub, not a refusal" \
  || no "a stranger sees an empty hub, not a refusal" "saw something"

# **The editor's own rewrite must not reach the page it publishes.** It turns
# `pic/` into `../pic/` so its frames resolve one level down; published, the
# same string resolves above the film and every picture breaks. It did, on his
# live bible. The payload is written to a file rather than quoted inline — see
# Ref 751 for why an escaped quote in a printf is not worth the argument.
printf '%s' '{"publish":"<figure><img src=\"../pic/abc.jpg\"></figure>"}' > "$STATE/rewrite.json"
body -X POST "$H/f/$FILM/bible/edit?as=$OWNER" -H 'content-type: application/json' --data @"$STATE/rewrite.json" >/dev/null
got=$(body "$H/f/$FILM/bible?as=$OWNER")
echo "$got" | grep -q '\.\./pic/' \
  && no "a published page keeps the film's own picture addresses" "the editor's rewrite was published" \
  || ok "a published page keeps the film's own picture addresses"

# **An empty page is not offered to a reader** — his walkthrough, 2026-09-23.
# A film with words on its bible and one crew member, and nothing else: the
# viewer's rail carries those two and not the spec sheet or Documents; his
# carries all four, the empty two drawn quiet; the address still answers.
EFILM="0000000000000000000000000000000e"
printf '{"format":1,"project":"%s","title":"Empty Rooms","engine":"0.1.0"}' "$EFILM" > "$STATE/efilm.json"
put "p/$EFILM/manifest.json" "$STATE/efilm.json"
printf '{"version":1,"people":[{"email":"%s","role":"viewer"}],"links":[],"invites":[]}' "$DIRECTOR" > "$STATE/efilm-people.json"
put "p/$EFILM/people.json" "$STATE/efilm-people.json"
printf '{"version":1,"look":"Warm and low.","status":"Development","crew":[{"name":"Ellis Ward","role":"Gaffer"}],"documents":[]}' > "$STATE/efilm-front.json"
put "p/$EFILM/front.json" "$STATE/efilm-front.json"
got=$(body "$H/f/$EFILM?as=$DIRECTOR")
echo "$got" | grep -q 'data-key="people"' \
  && ! echo "$got" | grep -q 'data-key="camera"' && ! echo "$got" | grep -q 'data-key="documents"' \
  && ok "an empty page is left off a reader's rail" || no "an empty page is left off a reader's rail" "rail"
# **The film page's paragraphs are not a bible** — his ruling, 2026-09-23. A
# Visual Language on the card fills the film's front page, not the bible.
! echo "$got" | grep -q 'data-key="bible"' && echo "$got" | grep -q 'Visual Language</div><p>Warm and low.' \
  && ok "…and the Visual Language is the film's own words, not a bible" || no "…and the Visual Language is the film's own words, not a bible" "bible row, or no words on the front"
got=$(body "$H/f/$EFILM?as=$OWNER")
! echo "$got" | grep -q 'data-key="camera"' && ! echo "$got" | grep -q 'data-key="documents"' \
  && ! echo "$got" | grep -q 'data-key="bible"' && echo "$got" | grep -q 'class="to" data-key="people"' \
  && ok "…and off his own too (his ruling, 2026-09-23)" || no "…and off his own too (his ruling, 2026-09-23)" "empty rows on his rail"
body "$H/f/$EFILM/camera?as=$OWNER" | grep -q 'class="to on empty" data-key="camera"' \
  && ok "…except the one he is standing on" || no "…except the one he is standing on" "no row for the page he is on"
[ "$(code "$H/f/$EFILM/camera?as=$DIRECTOR")" = 200 ] \
  && ok "…while its address still answers" || no "…while its address still answers" "not 200"
got=$(body "$H/f/$EFILM/add?as=$OWNER")
echo "$got" | grep -q '>Built In<' && echo "$got" | grep -q 'Camera Spec Sheet</b><span>Notion · Camera Spec Sheets</span><i class="none">Empty' \
  && ok "Add names every built-in page and says which are empty" || no "Add names every built-in page and says which are empty" "no Built In table"
echo "$got" | grep -q 'class="sharebtn' && ! echo "$got" | grep -q '/visibility">What Viewers See<' \
  && ok "…and Add wears the same rail foot as every page" || no "…and Add wears the same rail foot as every page" "no Share, or Visibility still there"
got=$(body "$H/?as=$OWNER")
echo "$got" | grep -q 'data-shelftools' && echo "$got" | grep -q 'data-status="Development"' && echo "$got" | grep -q '/shelf.js' \
  && ok "the shelf carries its search, Status, sort and Grid | List" || no "the shelf carries its search, Status, sort and Grid | List" "no shelf tools"

# ---- his home page's sort and folds, 2026-10-05 ------------------------------
# **His own shelf and nobody else's.** Next Date / Name / Recently Changed /
# Status, No Groups, and stages that fold are drawn by `public/shelf.js` where
# the page says `data-owner` — and the server says it only to an administrator,
# and sends the dates they sort on only to him. `home.mjs` drives the real thing
# in a browser; this is what each person is *sent*.
got=$(body "$H/?as=$OWNER")
echo "$got" | grep -q 'data-shelftools data-owner hidden' && echo "$got" | grep -q 'data-ownersort' && echo "$got" | grep -q 'aria-haspopup="menu"' \
  && ok "his shelf is told it is his, and offers the sort menu" || no "his shelf is told it is his, and offers the sort menu" "no data-owner"
echo "$got" | grep -q 'class="pcard[^>]*data-next="[^"]*" data-last="[^"]*" data-edited="' \
  && ok "…its cards carrying the dates it sorts on" || no "…its cards carrying the dates it sorts on" "no data-next"
! echo "$got" | grep -q '<select data-shelfsort' \
  && ok "…in place of the old select" || no "…in place of the old select" "both drawn"
got=$(body "$H/?as=$DIRECTOR")
echo "$got" | grep -q 'data-shelftools' && ! echo "$got" | grep -q 'data-owner\|data-ownersort\|data-next=\|data-last=\|data-edited=' \
  && echo "$got" | grep -q '<select data-shelfsort' \
  && ok "a viewer's shelf is exactly what it was: no sort menu, no folds, no dates" || no "a viewer's shelf is exactly what it was" "owner markup reached a viewer"
got=$(body "$H/?k=$KEY")
! echo "$got" | grep -q 'data-owner\|data-ownersort\|data-next=' \
  && ok "…and a share link's holder gets none of it either" || no "…and a share link's holder gets none of it either" "owner markup reached a link"
got=$(body "$H/shelf.js")
echo "$got" | grep -q 'localStorage.setItem(KEY' && ! echo "$got" | grep -q 'fetch(' \
  && ok "what he picks is kept in the browser, and the script sends nothing anywhere" || no "what he picks is kept in the browser" "the shelf script fetches"
echo "$got" | grep -q 'aria-expanded' && echo "$got" | grep -q 'menuitemradio' && echo "$got" | grep -q 'ArrowDown' \
  && ok "the headings are buttons that say if they are open; the menu answers the arrow keys" || no "the headings are buttons that say if they are open" "no aria"

# ---- his six answers of 2026-09-23 ------------------------------------------
# Ref 1158: the shelf starts on Active, and Shoot Date is newest first. The
# choice lives in the script (the tools are hidden with none), so it is read
# off the script itself; the rest is photographed.
got=$(body "$H/shelf.js")
echo "$got" | grep -q 'status: "Active"' && echo "$got" | grep -q '"shelf.v2"' \
  && ok "the shelf starts on Active" || no "the shelf starts on Active" "default is not Active"
echo "$got" | grep -q '(b.dataset.shoot || "").localeCompare(a.dataset.shoot' \
  && ok "…and Shoot Date sorts newest first" || no "…and Shoot Date sorts newest first" "oldest first"

# Ref 1160: the Share panel wears the portal's dark tokens even on a device in
# light mode — it is appended to the body, outside every `.fh2`.
body "$H/hub.css" | grep -q '^\.fh2, \.shroud {' \
  && ok "the Share panel is dark whatever the device prefers" || no "the Share panel is dark whatever the device prefers" "no .shroud in the dark block"

# Ref 1154: Visibility is a table — each person once, Shown and Contact side
# by side — and the same form is the Share panel's Visibility tab (Ref 1153).
got=$(body "$H/f/$EFILM/visibility?part=1&as=$OWNER")
echo "$got" | grep -q 'class="fh-visform"' && ! echo "$got" | grep -q 'class="rail"' \
  && ok "Visibility's table comes on its own, for the Share panel's tab" || no "Visibility's table comes on its own, for the Share panel's tab" "fragment"
[ "$(echo "$got" | grep -c 'value="Ellis Ward"')" = 2 ] && echo "$got" | grep -q 'name="contact" value="Ellis Ward"' \
  && ! echo "$got" | grep -q 'me-crew' \
  && echo "$got" | grep -q '<table class="vtable">' && ! echo "$got" | grep -q 'Contact Info' \
  && ok "…each person on one row, Shown and Contact side by side" || no "…each person on one row, Shown and Contact side by side" "listed twice or no table"
[ "$(code "$H/f/$EFILM/visibility?part=1&as=$DIRECTOR")" = 403 ] \
  && ok "…and the table is still his alone" || no "…and the table is still his alone" "not 403"

# Move 3 (Share beside the button): the popover's second tab is the same
# choices as a checklist, `?part=2`, under the sidebar's own headings, and it
# saves through the same address.
got=$(body "$H/f/$EFILM/visibility?part=2&as=$OWNER")
echo "$got" | grep -q 'class="sp-vform"' && ! echo "$got" | grep -q 'class="rail"' && echo "$got" | grep -q 'class="sp-grp"' \
  && echo "$got" | grep -q 'name="sections" value="people"' && echo "$got" | grep -q 'name="contact" value="Ellis Ward"' \
  && ! echo "$got" | grep -q 'me-sections\|For Me\|On Links' && echo "$got" | grep -q 'class="sp-lk"' && ! echo "$got" | grep -q 'class="vtrack"' \
  && ok "the Share popover's checklist comes on its own, with ticks" || no "the Share popover's checklist comes on its own, with ticks" "fragment"
[ "$(code "$H/f/$EFILM/visibility?part=2&as=$DIRECTOR")" = 403 ] \
  && ok "…and the checklist is still his alone" || no "…and the checklist is still his alone" "not 403"

got=$(body "$H/f/$EFILM/visibility?as=$OWNER")
echo "$got" | grep -q 'class="fh-visform"' && echo "$got" | grep -q 'class="rail"' \
  && ok "…and the plain page draws the same table in the rail" || no "…and the plain page draws the same table in the rail" "page"
got=$(body "$H/f/$EFILM?as=$OWNER")
# Share is Access alone (2026-10-11): no page leads to a Visibility tab.
echo "$got" | grep -q '"admin":true' && ! echo "$got" | grep -q 'data-tab="visibility"' \
  && grep -q 'const VIS_TAB = false' "$HERE/public/share.js" \
  && ok "the Share panel is Access alone, with no What Viewers See tab" || no "the Share panel is Access alone" "a way in to the tab is still drawn"

# Ref 1153: every page's own menu, and Shown on Links in it.
got=$(body "$H/f/$EFILM/bible?as=$OWNER")
echo "$got" | grep -q 'class="pagemenu"' && echo "$got" | grep -q 'name="flip" value="sections:bible"' \
  && ok "a page carries its own menu, with Private" || no "a page carries its own menu, with Private" "no menu"
body "$H/f/$EFILM/bible?as=$DIRECTOR" | grep -q 'class="pagemenu"' \
  && no "a reader is offered no page menu" "menu drawn for a viewer" || ok "a reader is offered no page menu"
# People, because it is the page with something on it — an empty bible is
# off a reader's rail whatever Shown on Links says.
[ "$(code -X POST -d 'flip=sections:people&back=people' "$H/f/$EFILM/visibility?as=$OWNER")" = 303 ] \
  && ! body "$H/f/$EFILM?as=$DIRECTOR" | grep -q 'data-key="people"' \
  && ok "…and it takes that one page off a reader's rail" || no "…and it takes that one page off a reader's rail" "still shown"
body -X POST -d 'flip=sections:people&back=people' "$H/f/$EFILM/visibility?as=$OWNER" >/dev/null
body "$H/f/$EFILM?as=$DIRECTOR" | grep -q 'data-key="people"' \
  && ok "…and back again, leaving everything else alone" || no "…and back again, leaving everything else alone" "not back"
[ "$(code -X POST -d 'flip=sections:bible&back=bible' "$H/f/$EFILM/visibility?as=$DIRECTOR")" = 403 ] \
  && ok "…and only he may flip it" || no "…and only he may flip it" "not 403"

# Rename, from the menu: the name changes, and the address follows it (his
# ask, 2026-10-09). The old address forwards, so a link already sent works.
body -X POST -d 'type=page&name=Scratch+Notes' "$H/f/$EFILM/add?as=$OWNER" >/dev/null
body -X POST -d 'markdown=%23+Notes%0A%0AKeep+these.' "$H/f/$EFILM/scratch-notes?as=$OWNER" >/dev/null
got=$(body "$H/f/$EFILM/scratch-notes?as=$OWNER")
echo "$got" | grep -q 'href="#pa-rename"' && echo "$got" | grep -q 'name="rename"' && echo "$got" | grep -q 'href="#pa-remove"' \
  && ok "a page he made offers Rename and Remove in its menu" || no "a page he made offers Rename and Remove in its menu" "menu items"
[ "$(header "$H/f/$EFILM/scratch-notes?as=$OWNER" location)" = "" ] \
  && [ "$(curl -s -o /dev/null -w '%header{location}' -X POST -d 'rename=Rough+Notes' "$H/f/$EFILM/scratch-notes?as=$OWNER")" = "/f/$EFILM/rough-notes" ] \
  && body "$H/f/$EFILM/rough-notes?as=$OWNER" | grep -q '<span class="nm">Rough Notes</span>' \
  && body "$H/f/$EFILM/rough-notes?as=$OWNER" | grep -q 'href="/f/'"$EFILM"'/rough-notes"' \
  && body "$H/f/$EFILM/rough-notes?as=$OWNER" | grep -q 'Keep these.' \
  && ok "…and Rename moves the address to the new name, words and all" || no "…and Rename moves the address to the new name" "name, address or words"
got=$(body "$H/f/$EFILM/rough-notes?as=$OWNER&k=x")
echo "$got" | grep -q 'property="og:title" content="Rough Notes · ' && echo "$got" | grep -q 'cover.png?page=rough-notes' \
  && ok "…and its link preview names it by the new name" || no "…and its link preview names it by the new name" "og"
[ "$(code "$H/f/$EFILM/scratch-notes?as=$OWNER")" = 301 ] \
  && [ "$(header "$H/f/$EFILM/scratch-notes?as=$OWNER" location)" = "/f/$EFILM/rough-notes?as=$OWNER" ] \
  && ok "…and the old address forwards to the new one" || no "…and the old address forwards to the new one" "not 301 there"
body -X POST -d 'rename=Loose+Notes' "$H/f/$EFILM/rough-notes?as=$OWNER" >/dev/null
[ "$(header "$H/f/$EFILM/scratch-notes?as=$OWNER" location)" = "/f/$EFILM/loose-notes?as=$OWNER" ] \
  && [ "$(header "$H/f/$EFILM/rough-notes?as=$OWNER" location)" = "/f/$EFILM/loose-notes?as=$OWNER" ] \
  && ok "…and every older address goes straight to the newest" || no "…and every older address goes straight to the newest" "chain"
[ "$(code -X POST -d 'rename=People' "$H/f/$EFILM/loose-notes?as=$OWNER")" = 409 ] \
  && ok "…and refuses a name another page wears" || no "…and refuses a name another page wears" "not 409"
# His rule, 2026-10-09: every old link keeps working, unless the page is
# deleted or private. A private page's old link answers nothing to a reader,
# and does not give its new name away by forwarding there.
body -X POST -d 'flip=sections:loose-notes&back=loose-notes' "$H/f/$EFILM/visibility?as=$OWNER" >/dev/null
[ "$(code "$H/f/$EFILM/scratch-notes?as=$DIRECTOR")" = 404 ] && [ "$(header "$H/f/$EFILM/scratch-notes?as=$DIRECTOR" location)" = "" ] \
  && [ "$(code "$H/f/$EFILM/scratch-notes?as=$OWNER")" = 301 ] \
  && ok "…and a private page's old link opens nothing for a reader" || no "…and a private page's old link opens nothing for a reader" "forwarded"
body -X POST -d 'flip=sections:loose-notes&back=loose-notes' "$H/f/$EFILM/visibility?as=$OWNER" >/dev/null
[ "$(code "$H/f/$EFILM/scratch-notes?as=$DIRECTOR")" = 301 ] \
  && ok "…and opens again when the page is shown again" || no "…and opens again when the page is shown again" "not 301"
body -X POST -d 'remove=1' "$H/f/$EFILM/loose-notes?as=$OWNER" >/dev/null
body -X POST -d 'type=page&name=Rough+Notes' "$H/f/$EFILM/add?as=$OWNER" >/dev/null
[ "$(code "$H/f/$EFILM/scratch-notes?as=$OWNER")" = 404 ] && [ "$(code "$H/f/$EFILM/rough-notes?as=$OWNER")" = 200 ] \
  && ok "…and a deleted page's old links die with it, never reaching a new page" || no "…and a deleted page's old links die with it" "still forwards"
body -X POST -d 'remove=1' "$H/f/$EFILM/rough-notes?as=$OWNER" >/dev/null

# Ref 1161, item 2: ⌘K. The box is `jump.js`; its films are the shelf's own
# list, and nobody else's.
got=$(body "$H/films.json?as=$OWNER")
echo "$got" | grep -q '"title":"Empty Rooms","base":"/emptyrooms"' \
  && ok "⌘K knows his films" || no "⌘K knows his films" "$got"
[ "$(body "$H/films.json?as=$STRANGER")" = '{"films":[]}' ] \
  && ok "…and a stranger's list is empty" || no "…and a stranger's list is empty" "listed something"
body "$H/f/$EFILM?as=$OWNER" | grep -q '/jump.js' && body "$H/film.js" | grep -q 'window.shotlisterJump = ' \
  && ok "…and every film page carries it, with the program's scenes and places" || no "…and every film page carries it, with the program's scenes and places" "no jump.js"

# Ref 1161, item 1: the card opens into the film — the pressed card takes the
# two names that travel between a film's screens.
body "$H/shelf.js" | grep -q 'viewTransitionName = on ? "filmmark"' \
  && ok "a shelf card hands its mark to the film it opens" || no "a shelf card hands its mark to the film it opens" "no names"

# Ref 1161, item 4, and Ref 1155: how fresh the words are, on every page, for
RFILM="00000000000000000000000000c0ff03"
printf '{"format":1,"project":"%s","title":"Refresh Film","engine":"0.1.0"}' "$RFILM" > "$STATE/rf.json"
put "p/$RFILM/manifest.json" "$STATE/rf.json"
printf '{"version":1,"people":[{"email":"%s","role":"editor"}],"links":[],"invites":[]}' "$DIRECTOR" > "$STATE/rf.json"
put "p/$RFILM/people.json" "$STATE/rf.json"
printf '{"version":1,"status":"Development","linked":"name","updated":"2026-01-01T00:00:00Z","logline":"The portal'"'"'s own line.","sections":[{"slug":"gone-from-notion","name":"Gone From Notion"},{"slug":"overheads-from-notion","name":"Overheads From Notion","title":"Overheads Page","source":"notion","notion":true,"type":"page","from":"aaaaaaaabbbbccccdddd000000000001"}],"documents":[{"name":"His Upload","file":"0123456789abcdef0123456789abcdef.pdf","source":"here"}]}' > "$STATE/rf.json"
put "p/$RFILM/front.json" "$STATE/rf.json"
# him — with Refresh beside it, because this run gives the portal a Notion.
got=$(body "$H/f/$RFILM/camera?as=$OWNER")
echo "$got" | grep -q 'class="railfresh"' && echo "$got" | grep -q 'class="railfreshgo"' \
  && ok "every page says how fresh it is, with Refresh" || no "every page says how fresh it is, with Refresh" "no line"
body "$H/f/$RFILM/camera?as=$DIRECTOR" | grep -q 'railfresh' \
  && no "…and only to him" "a viewer sees it" || ok "…and only to him"
[ "$(code -X POST -d back=camera "$H/f/$RFILM/refresh?as=$DIRECTOR")" = 403 ] \
  && ok "…and only he may refresh" || no "…and only he may refresh" "not 403"
[ "$(code -X POST -d back=camera "$H/f/$RFILM/refresh?as=$OWNER")" = 303 ] \
  && ok "Refresh from Notion runs on the portal" || no "Refresh from Notion runs on the portal" "not 303"
# His rule, 2026-10-17: the logline and everything else come from the portal
# and the project record. Only a page set up to follow Notion (Live from
# Notion, with the Notion page it came from) is drawn again, from that page.
got=$(body "$H/f/$RFILM?as=$OWNER")
echo "$got" | grep -q "The portal&#39;s own line.\|The portal's own line." && ! echo "$got" | grep -q 'A logline from the Logline box.' && ! echo "$got" | grep -q 'A logline that came from the fake Notion.' \
  && ok "…and keeps the portal's own logline, never Notion's" || no "…and keeps the portal's own logline, never Notion's" "logline"
body "$H/f/$RFILM/people?as=$OWNER" | grep -q 'Clara Notion' \
  && no "…and brings no people from Notion" "crew came over" || ok "…and brings no people from Notion"
got=$(body "$H/f/$RFILM/documents?as=$OWNER")
echo "$got" | grep -q 'Call Sheet From Notion\|Not Ticked' \
  && no "…and no documents from Notion" "documents came over" || ok "…and no documents from Notion"
got=$(body "$H/f/$RFILM/overheads-from-notion?as=$OWNER")
echo "$got" | grep -q 'Two overheads on the east wall.' && echo "$got" | grep -q 'Two 12x12 frames' \
  && ok "…a page that follows Notion is drawn again from its own Notion page, toggles and all" || no "…a page that follows Notion is drawn again from its own Notion page" "page"
got=$(body "$H/f/$RFILM/camera?as=$OWNER")
echo "$got" | grep -q 'ARRI Alexa 35' \
  && no "…and no spec sheet from Notion" "sheet came over" || ok "…and no spec sheet from Notion"

echo "$(body "$H/f/$RFILM/documents?as=$OWNER")" | grep -q 'His Upload' \
  && ok "…keeping a document he uploaded" || no "…keeping a document he uploaded" "upload swept away"
echo "$(body "$H/f/$RFILM?as=$OWNER")" | grep -q 'data-key="gone-from-notion"' \
  && ok "…and leaving a page Notion does not name alone" || no "…and leaving a page Notion does not name alone" "dropped from the rail"

echo
# ---- Notion's shoot days, until the film has its own -------------------------
# His report and ruling, 2026-09-23: Halcyon's shoot dates were not detected.
# A project with no film has no schedule; until Shotlister takes over, its
# Notion Shoot Dates are its days — for Next Day.
SFILM="${PAGE%?}8"
body -X PUT "${CONSOLE[@]}" -d "$(printf '{"page":"%s","name":"Stills Day","stage":"Active","lights":{"drive":"on"}}' "$SFILM")" "$H/console/record/$SFILM" >/dev/null
body -X PUT "${CONSOLE[@]}" -d '{"title":"Stills Day","by":"console"}' "$H/console/$SFILM/portal" >/dev/null
S1=$(date -u -v+30d +%F); S2=$(date -u -v+32d +%F)
printf '{"version":1,"film":false,"status":"Active","linked":"link","source":"notion:%s","shoot":{"start":"%s","end":"%s"},"days":[],"sections":[],"documents":[]}' "$SFILM" "$S1" "$S2" > /tmp/hubcheck-sfilm-front.json
put "p/$SFILM/front.json" /tmp/hubcheck-sfilm-front.json
rm -f /tmp/hubcheck-sfilm-front.json
D1=$(date -u -v+30d "+%a %-d %b")
body "$H/f/$SFILM?as=$OWNER" | grep -q "Next Day</span><span class=\"hm-ndt\"><b>$D1" \
  && ok "a project with no film takes its next day from Notion's shoot dates" \
  || no "a project with no film takes its next day from Notion's shoot dates" "$(body "$H/f/$SFILM?as=$OWNER" | grep -o 'Next Day.\{0,60\}' | head -1)"

# Ref 1161, item 5, folded in 2026-10-02: Coming Up's one job — the next shoot
# day — is now said once, on the card it names, instead of twice.
NSFILM="00000000000000000000000000c0ff06"
printf '{"format":1,"project":"%s","title":"No Shoot Film","engine":"0.1.0"}' "$NSFILM" > "$STATE/ns.json"
put "p/$NSFILM/manifest.json" "$STATE/ns.json"
printf '{"version":1,"status":"Post"}' > "$STATE/ns.json"
put "p/$NSFILM/front.json" "$STATE/ns.json"
strip=$(body "$H/?as=$OWNER" | tr -d '\n')
# `awk`'s `substr`, not a grep interval: BSD grep refuses `\{0,900\}` outright
# ("maximum repetition exceeds 255"), so a card's markup — comfortably past
# that — needs cutting out by position instead.
card() { awk -v t="data-title=\"$1\"" '{i=index($0,t); if(i) print substr($0,i,900)}'; }
echo "$strip" | grep -oq "class=\"pcard haswhen\"[^>]*data-title=\"Stills Day\"" \
  && ok "the shelf card folds in the film's next shoot day" || no "the shelf card folds in the film's next shoot day" "no haswhen"
echo "$strip" | card "Stills Day" | grep -q "class=\"when\"><b>$D1</b><span>30 days</span>" \
  && ok "…with the date and how far off, the way Coming Up said them" \
  || no "…with the date and how far off, the way Coming Up said them" "$(echo "$strip" | card "Stills Day")"
echo "$strip" | grep -oq "class=\"pcard haswhen\"[^>]*data-title=\"No Shoot Film\"" \
  && no "…and a film with nothing ahead gets no when" "$(echo "$strip" | card "No Shoot Film")" || ok "…and a film with nothing ahead gets no when"

# His report, 2026-09-25: the home page did not follow a shoot date moved in
# Notion. A film's own days win only while they sit inside Notion's range; a
# schedule left behind when the shoot moved gives way to Notion. Checked
# through each film's own Next Day, which reads the same fallback.
for pair in "00000000000000000000000000c0ff04:Moved Film:+10d:+11d:+40d:+40d" "00000000000000000000000000c0ff05:Kept Film:+50d:+51d:+49d:+52d"; do
  IFS=: read -r id name a b s e <<< "$pair"
  printf '{"format":1,"project":"%s","title":"%s","engine":"0.1.0"}' "$id" "$name" > "$STATE/mv.json"
  put "p/$id/manifest.json" "$STATE/mv.json"
  printf '{"version":1,"status":"Active","shoot":{"start":"%s","end":"%s"},"days":[{"label":"Own One","date":"%s"},{"label":"Own Two","date":"%s"}]}' \
    "$(date -u -v"$s" +%F)" "$(date -u -v"$e" +%F)" "$(date -u -v"$a" +%F)" "$(date -u -v"$b" +%F)" > "$STATE/mv.json"
  put "p/$id/front.json" "$STATE/mv.json"
done
M1=$(date -u -v+40d "+%a %-d %b")
K1=$(date -u -v+50d "+%a %-d %b")
body "$H/f/00000000000000000000000000c0ff04?as=$OWNER" | grep -q "Next Day</span><span class=\"hm-ndt\"><b>$M1" \
  && ok "a shoot moved in Notion moves its Next Day, past a schedule left behind" \
  || no "a shoot moved in Notion moves its Next Day, past a schedule left behind" "$(body "$H/f/00000000000000000000000000c0ff04?as=$OWNER" | grep -o 'Next Day.\{0,60\}' | head -1)"
body "$H/f/00000000000000000000000000c0ff05?as=$OWNER" | grep -q "Next Day</span><span class=\"hm-ndt\"><b>$K1" \
  && ok "…and a schedule inside Notion's range still wins" || no "…and a schedule inside Notion's range still wins" "$(body "$H/f/00000000000000000000000000c0ff05?as=$OWNER" | grep -o 'Next Day.\{0,60\}' | head -1)"
got=$(body "$H/f/00000000000000000000000000c0ff04?as=$OWNER")
echo "$got" | grep -q 'data-coming' && [ "$(echo "$got" | grep -c 'class="hm-nd"')" = 1 ] && ! echo "$got" | grep -q 'aria-label="Properties"\|class="hm-day' \
  && ok "the film's home carries one Next Day line and no Properties panel" || no "the film's home carries one Next Day line and no Properties panel" "no line, or a panel"
! body "$H/f/$NOFILM?as=$OWNER" | grep -q 'data-coming' \
  && ok "…and a film with no days ahead draws no Next Day" || no "…and a film with no days ahead draws no Next Day" "drawn"

echo
# ---- boards: a page of their own, his until he shares it ---------------------
# His idea of 2026-09-24 and his rulings of 2026-09-25: the Halcyon board as a
# page any film can have, many times over; private first, shared when he
# chooses (Only Me, Crew, Anyone with the Link); pictures and links added from
# the page; and the MCP able to build one. `src/boards.js`.
BKEY="boardcheckkeyboardcheckkey01"
BHASH=$(printf %s "$BKEY" | shasum -a 256 | cut -d' ' -f1)
VIEWER="ava@example.com"
sent=$(printf '{"people":[{"email":"%s","role":"editor"},{"email":"%s","role":"viewer"}],"links":[{"hash":"%s","role":"viewer","expires":null}]}' "$DIRECTOR" "$VIEWER" "$BHASH")
code -X PUT -H 'content-type: application/json' -d "$sent" "$H/f/$FILM/api/people?as=$OWNER" >/dev/null
body "$H/f/$FILM/add?as=$OWNER" | grep -q 'name="type" value="board"' \
  && ok "Add offers a Board" || no "Add offers a Board" "no board type"
loc=$(curl -s -o /dev/null -w "%{redirect_url}" -X POST -F type=board -F "name=Night Look" "$H/f/$FILM/add?as=$OWNER")
echo "$loc" | grep -q "/night-look$" && ok "…and makes one, and opens it" || no "…and makes one, and opens it" "${loc:-no redirect}"
got=$(body "$H/f/$FILM/night-look?as=$OWNER")
BNAME=$(echo "$got" | grep -o 'data-bd="night-look-[0-9a-f]*"' | head -1 | cut -d'"' -f2)
[ -n "$BNAME" ] && echo "$got" | grep -q "data-api=\"/f/$FILM/api/board/$BNAME\"" && echo "$got" | grep -q '/board.js' \
  && ok "…a board that says where it saves" || no "…a board that says where it saves" "${BNAME:-no board}"
B="$H/f/$FILM/api/board/$BNAME"
[ "$(code "$H/f/$FILM/night-look?as=$DIRECTOR")" = 404 ] && [ "$(code "$B?as=$DIRECTOR")" = 404 ] \
  && ok "a new board is his alone — the crew get nothing, page or cards" || no "a new board is his alone — the crew get nothing, page or cards" "crew can see it"
body "$H/f/$FILM/documents?as=$DIRECTOR" | grep -q 'data-key="night-look"' \
  && no "…not even its name on the rail" "on the rail" || ok "…not even its name on the rail"
body "$H/f/$FILM/api/front?as=$DIRECTOR" | grep -q 'night-look' \
  && no "…or in the film's card" "in the card" || ok "…or in the film's card"
body "$H/f/$FILM/documents?as=$OWNER" | grep -q 'data-key="night-look"' \
  && ok "…while it is on his own rail" || no "…while it is on his own rail" "not on his rail"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"share":"link"}' "$B/share?as=$DIRECTOR")" = 404 ] \
  && ok "…and a crew editor cannot share it" || no "…and a crew editor cannot share it" "shared"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"share":"crew"}' "$B/share?as=$OWNER")" = 200 ] \
  && [ "$(code "$H/f/$FILM/night-look?as=$VIEWER")" = 200 ] && [ "$(code "$B?as=$VIEWER")" = 200 ] \
  && ok "shared with the crew, anybody signed in opens it" || no "shared with the crew, anybody signed in opens it" "crew refused"
[ "$(code "${SHARE[@]}" "$H/f/$FILM/night-look?k=$BKEY")" = 404 ] && [ "$(code "${SHARE[@]}" "$B?k=$BKEY")" = 404 ] \
  && ok "…and the share link still does not" || no "…and the share link still does not" "link let in"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"share":"link"}' "$B/share?as=$OWNER")" = 200 ] \
  && [ "$(code "${SHARE[@]}" "$H/f/$FILM/night-look?k=$BKEY")" = 200 ] \
  && ok "shared with the link, the link opens it" || no "shared with the link, the link opens it" "link refused"
[ "$(code -X PUT "${SHARE[@]}" -H 'content-type: application/json' -d '{"added":[]}' "$B?k=$BKEY")" = 403 ] \
  && ok "…to look at, not to change" || no "…to look at, not to change" "link wrote"
body "$H/f/$FILM/visibility?part=1&as=$OWNER" | tr -d '\n' | grep -q 'name="sections" value="night-look" checked' \
  && ok "…and Visibility shows it on Links" || no "…and Visibility shows it on Links" "not shown as on"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"share":"everyone"}' "$B/share?as=$OWNER")" = 400 ] \
  && ok "only the three answers are taken" || no "only the three answers are taken" "took a fourth"
python3 -c "
import zlib,struct,sys
raw=b''.join(b'\x00'+bytes([200,120,60]*32) for _ in range(18))
ch=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',32,18,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))" "$STATE/board.png"
got=$(curl -s -X PUT -H 'content-type: image/png' --data-binary "@$STATE/board.png" "$B/upload?name=frame.png&as=$OWNER")
src=$(echo "$got" | python3 -c "import sys,json;print(json.load(sys.stdin).get('src',''))" 2>/dev/null)
[ -n "$src" ] && [ "$(code "$H/f/$FILM/$src?as=$OWNER")" = 200 ] \
  && ok "a picture dropped on a board is kept on the film" || no "a picture dropped on a board is kept on the film" "$got"
[ "$(code -X PUT -H 'content-type: text/plain' --data 'words' "$B/upload?name=a.txt&as=$OWNER")" = 415 ] \
  && ok "…and only pictures and clips are" || no "…and only pictures and clips are" "took words"
[ "$(code -X PUT "${SHARE[@]}" -H 'content-type: image/png' --data-binary "@$STATE/board.png" "$B/upload?k=$BKEY")" = 403 ] \
  && ok "…and never from a link that may only look" || no "…and never from a link that may only look" "link uploaded"
sent='{"v":1,"lenses":[{"id":"light","type":"line","name":"Dark ↔ Bright","ends":["Dark","Bright"]}],"added":[{"id":"note-1","kind":"note","x":0,"y":0,"text":"a thought","vals":{"light":0.2}}],"ties":[]}'
[ "$(code -X PUT -H 'content-type: application/json' -d "$sent" "$B?as=$OWNER")" = 200 ] \
  && body "$B?as=$OWNER" | grep -q '"name":"Dark ↔ Bright"' \
  && ok "a board keeps its own sorts" || no "a board keeps its own sorts" "sorts lost"
[ "$(code -X PUT -H 'content-type: application/json' -d '{"share":"me"}' "$B/share?as=$OWNER")" = 200 ] \
  && [ "$(code "${SHARE[@]}" "$H/f/$FILM/night-look?k=$BKEY")" = 404 ] && [ "$(code "$B?as=$DIRECTOR")" = 404 ] \
  && ok "…and goes back to his alone in one move" || no "…and goes back to his alone in one move" "still open"
got=$(said "$(tell '{"jsonrpc":"2.0","id":80,"method":"tools/call","params":{"name":"open_project","arguments":{"film":"Daybreak"}}}')")
got=$(said "$(tell '{"jsonrpc":"2.0","id":81,"method":"tools/call","params":{"name":"boards"}}')")
echo "$got" | grep -q '"slug": "night-look"' && echo "$got" | grep -q 'only him' \
  && ok "the MCP lists his boards to him" || no "the MCP lists his boards to him" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":82,"method":"tools/call","params":{"name":"add_board","arguments":{"name":"Car Scenes","sorts":[{"name":"Camera","type":"columns","columns":["A-cam","B-cam"]}]}}}')")
echo "$got" | grep -q 'car-scenes' && echo "$got" | grep -q 'his alone' \
  && ok "…makes one, his alone" || no "…makes one, his alone" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"set_board","arguments":{"slug":"car-scenes","add":[{"kind":"heading","text":"Night"},{"kind":"scene","scene":"33","values":{"Camera":"B-cam"}}]}}}')")
echo "$got" | grep -q '2 cards added' && ok "…fills it" || no "…fills it" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":84,"method":"tools/call","params":{"name":"board","arguments":{"slug":"car-scenes"}}}')")
echo "$got" | grep -q '"Camera": "B-cam"' && echo "$got" | grep -q '"type": "scene"' \
  && ok "…and reads it back, sorted, from the film" || no "…and reads it back, sorted, from the film" "$got"
# Columns named by bare words carry no subtitle — not String's own `sub` method.
capi=$(body "$H/f/$FILM/car-scenes?as=$OWNER" | grep -o 'data-api="[^"]*"' | head -1 | cut -d'"' -f2)
got=$(body "$H$capi?as=$OWNER")
echo "$got" | grep -q '"B-cam"' && ! echo "$got" | grep -q 'native code' \
  && ok "…its columns named by words, with no stray subtitle" || no "…its columns named by words, with no stray subtitle" "$capi $(echo "$got" | head -c 300)"
got=$(said "$(tell '{"jsonrpc":"2.0","id":85,"method":"tools/call","params":{"name":"set_board","arguments":{"slug":"car-scenes","add":[{"kind":"scene","scene":"33","values":{"Camera":"C-cam"}}]}}}')")
echo "$got" | grep -q 'no column called C-cam' && ok "…refusing a column it does not have" || no "…refusing a column it does not have" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":86,"method":"tools/call","params":{"name":"set_page","arguments":{"name":"Car Scenes","markdown":"words"}}}')")
echo "$got" | grep -q 'is a board' && ok "…and words are not written onto a board" || no "…and words are not written onto a board" "$got"


# ---- Boards, first round of his notes (2026-09-25) ---------------------------
# A picture on a board goes onto a shot only when he asks (Add to Shot): the
# file joins the film's own pictures and the engine files it on the shot as a
# change log, once. A clip asked for as .mov is answered with its .mp4 proxy.
got=$(body -X POST -H 'content-type: application/json' -d "{\"src\":\"$src\",\"shot\":\"33A\",\"caption\":\"from the board\"}" "$B/attach?as=$OWNER")
echo "$got" | grep -q 'Added to Shot 33A' && ok "a board picture is added to a shot when asked" || no "a board picture is added to a shot when asked" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":87,"method":"tools/call","params":{"name":"attachments","arguments":{"shot":"33A"}}}')")
echo "$got" | grep -q 'Board Still' && ok "…and the film has it on that shot" || no "…and the film has it on that shot" "$got"
[ "$(code "$H/f/$FILM/media/${src#pic/}?as=$OWNER")" = 200 ] \
  && ok "…kept beside the film's own pictures" || no "…kept beside the film's own pictures" "not in media/"
got=$(body -X POST -H 'content-type: application/json' -d "{\"src\":\"$src\",\"shot\":\"33A\"}" "$B/attach?as=$OWNER")
echo "$got" | grep -q 'already has it' && ok "…and never twice" || no "…and never twice" "$got"
got=$(body -X POST -H 'content-type: application/json' -d "{\"src\":\"$src\",\"shot\":\"99Z\"}" "$B/attach?as=$OWNER")
echo "$got" | grep -q 'No shot called 99Z' && ok "…refusing a shot the film does not have" || no "…refusing a shot the film does not have" "$got"
[ "$(code -X POST -H 'content-type: application/json' -d '{"src":"pic/nothing.txt","shot":"33A"}' "$B/attach?as=$OWNER")" = 400 ] \
  && ok "…and anything that is not a picture on the film" || no "…and anything that is not a picture on the film" "took it"
printf 'not really a clip, but bytes' > "$STATE/clip.mp4"
put "p/$FILM/media/0123456789abcdef0123456789abcdef.mp4" "$STATE/clip.mp4"
got=$(curl -s -o /dev/null -w "%{http_code} %{content_type}" "$H/f/$FILM/media/0123456789abcdef0123456789abcdef.mov?as=$OWNER")
[ "$got" = "200 video/mp4" ] && ok "a clip asked for as .mov is answered with its .mp4" || no "a clip asked for as .mov is answered with its .mp4" "$got"

# A picture the film already holds (off its bible, its Reference Images) is put
# on a board where it is — its portal address answers only to the signed in.
own=$(H="$H" FILM="$FILM" SRC="$src" python3 -c "
import json, os
s = os.environ['SRC']
print(json.dumps({'jsonrpc': '2.0', 'id': 88, 'method': 'tools/call', 'params': {'name': 'set_board', 'arguments': {'slug': 'car-scenes', 'add': [
  {'kind': 'still', 'url': os.environ['H'] + '/f/' + os.environ['FILM'] + '/' + s},
  {'kind': 'ref', 'title': 'Own', 'stills': [s[4:]]},
  {'kind': 'still', 'url': 'pic/0123456789abcdef0123456789abcdee.jpg'}]}}}))")
got=$(said "$(tell "$own")")
echo "$got" | grep -q '2 cards added' && echo "$got" | grep -q 'Could not fetch 1' \
  && ok "a board takes a picture the film holds, by its own address" || no "a board takes a picture the film holds, by its own address" "$got"
got=$(said "$(tell '{"jsonrpc":"2.0","id":89,"method":"tools/call","params":{"name":"board","arguments":{"slug":"car-scenes"}}}')")
echo "$got" | grep -q "\"picture\": \"$src\"" && ok "…and draws it from the film" || no "…and draws it from the film" "$got"
# ---- Boards: the connector can do everything the board can (2026-09-25) -----
# His ask: "make the MCP fully functional inside the boards." Cards from the
# film made whole at once, the file itself, arranging, copying, threads,
# History, rename, the link switch and Add to Shot — through the MCP alone.
# `src/boards.js`, `src/arrange.js`.
mcall() { # mcall <id> <tool> <json args> — the reply's words
  # Built first, then sent: the Mac's bash 3.2 mangles quotes nested in "$(…)".
  local q="{\"jsonrpc\":\"2.0\",\"id\":$1,\"method\":\"tools/call\",\"params\":{\"name\":\"$2\",\"arguments\":$3}}"
  said "$(tell "$q")"
}
# No two cards on top of each other: every card's box, by its estimated size.
apart() { python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
cs = d['cards']
bad = [(a['id'], b['id']) for i, a in enumerate(cs) for b in cs[i+1:]
       if abs(a['x']-b['x'])*2 < a['w']+b['w'] and abs(a['y']-b['y'])*2 < a['h']+b['h']]
print('apart' if not bad else 'overlap %s' % bad[:3])" 2>&1; }
got=$(tell '{"jsonrpc":"2.0","id":120,"method":"tools/list"}')
printf '%s' "$got" | grep -q '"arrange_board"' && ok "the MCP offers arrange_board" || no "the MCP offers arrange_board" "not listed"
got=$(mcall 121 set_board '{"slug":"car-scenes","add":[{"kind":"shot","shot":"33A"},{"kind":"scene","scene":"33"}]}')
echo "$got" | grep -q '2 cards added' && ok "a shot and a scene go on from the film" || no "a shot and a scene go on from the film" "$got"
got=$(mcall 122 board '{"slug":"car-scenes"}')
echo "$got" | grep -q '"kicker": "Shot 33A"' && echo "$got" | grep -q '"kicker": "Scene 33"' \
  && ok "…made whole at once, as the board's own panel makes them" || no "…made whole at once, as the board's own panel makes them" "$got"
got=$(mcall 123 set_board '{"slug":"car-scenes","add":[{"kind":"shot","shot":"99Z"}]}')
echo "$got" | grep -q 'has no shot 99Z' && ok "…refusing a shot the film does not have" || no "…refusing a shot the film does not have" "$got"
B64=$(base64 < "$STATE/board.png" | tr -d '\n')
got=$(mcall 124 set_board "{\"slug\":\"car-scenes\",\"add\":[{\"kind\":\"still\",\"base64\":\"$B64\",\"filename\":\"frame.png\"},{\"kind\":\"note\",\"text\":\"one\"},{\"kind\":\"idea\",\"title\":\"Two\"},{\"kind\":\"gear\",\"title\":\"Three\"}]}")
STILL=$(echo "$got" | grep -o 'still-[a-z0-9]*' | head -1)
NOTE=$(echo "$got" | grep -o 'note-[a-z0-9]*' | head -1)
IDEA=$(echo "$got" | grep -o 'idea-[a-z0-9]*' | head -1)
GEAR=$(echo "$got" | grep -o 'gear-[a-z0-9]*' | head -1)
[ -n "$STILL" ] && [ -n "$GEAR" ] && ok "a picture sent as the file itself goes on" || no "a picture sent as the file itself goes on" "$got"
got=$(mcall 125 board '{"slug":"car-scenes"}')
echo "$got" | apart | grep -q '^apart' && ok "…and new cards are laid where nothing is" || no "…and new cards are laid where nothing is" "$(echo "$got" | apart)"
got=$(mcall 126 arrange_board '{"slug":"car-scenes","by":"kind"}')
echo "$got" | grep -q 'arranged' && echo "$got" | grep -q 'Headings made' && echo "$got" | grep -q 'History' \
  && ok "arrange_board groups a board by kind, headings and all" || no "arrange_board groups a board by kind, headings and all" "$got"
got=$(mcall 127 board '{"slug":"car-scenes"}')
echo "$got" | apart | grep -q '^apart' && echo "$got" | grep -q '"text": "Stills"' \
  && ok "…with nothing on top of anything" || no "…with nothing on top of anything" "$(echo "$got" | apart)"
got=$(mcall 128 arrange_board '{"slug":"car-scenes","by":"sort","sort":"Camera"}')
echo "$got" | grep -q 'Unsorted' && ok "…by a sort's columns" || no "…by a sort's columns" "$got"
got=$(mcall 129 arrange_board "{\"slug\":\"car-scenes\",\"by\":\"groups\",\"groups\":[{\"name\":\"Look\",\"cards\":[\"$IDEA\",\"$GEAR\"]}],\"near\":\"$STILL\",\"side\":\"below\"}")
got2=$(mcall 130 board '{"slug":"car-scenes"}')
echo "$got" | grep -q 'Look (2)' && echo "$got2" | apart | grep -q '^apart' \
  && ok "…into named groups, under a card that stays put" || no "…into named groups, under a card that stays put" "$got"
printf '%s' "$got2" | python3 -c "
import sys, json
d = json.load(sys.stdin); c = {x['id']: x for x in d['cards']}
s, g = c['$STILL'], c['$GEAR']
print('below' if g['y'] > s['y'] + s['h']/2 else 'not below')" | grep -q '^below' \
  && ok "…and it is under it" || no "…and it is under it" "not below"
got=$(mcall 131 arrange_board '{"slug":"car-scenes","by":"everything"}')
echo "$got" | grep -q '`by` is one of' && ok "…refusing a way it does not know" || no "…refusing a way it does not know" "$got"
got=$(mcall 132 set_board "{\"slug\":\"car-scenes\",\"tie\":[{\"a\":[\"$IDEA\",\"$GEAR\"],\"b\":\"$STILL\",\"label\":\"feel\"}]}")
echo "$got" | grep -q '2 tied' && ok "many cards tie to one under one label" || no "many cards tie to one under one label" "$got"
got=$(mcall 133 set_board "{\"slug\":\"car-scenes\",\"label\":[{\"a\":\"$IDEA\",\"b\":\"$STILL\",\"label\":\"mood\"}]}")
got2=$(mcall 134 board '{"slug":"car-scenes"}')
echo "$got2" | grep -q '"label": "mood"' && echo "$got2" | grep -q '"label": "feel"' \
  && ok "…and a thread's label changes" || no "…and a thread's label changes" "$got"
got=$(mcall 135 set_board "{\"slug\":\"car-scenes\",\"duplicate\":[\"$IDEA\",\"$GEAR\"]}")
got2=$(mcall 136 board '{"slug":"car-scenes"}')
[ "$(echo "$got2" | grep -c '"title": "Two"')" = 2 ] && echo "$got2" | apart | grep -q '^apart' \
  && ok "duplicate lays copies beside them, on nothing" || no "duplicate lays copies beside them, on nothing" "$got"
got=$(mcall 137 set_board "{\"slug\":\"car-scenes\",\"send\":{\"cards\":[\"$IDEA\"],\"to\":\"night-look\"}}")
echo "$got" | grep -q 'copied to Night Look' && mcall 138 board '{"slug":"night-look"}' | grep -q '"title": "Two"' \
  && ok "…and send copies cards onto another board" || no "…and send copies cards onto another board" "$got"
got=$(mcall 139 board '{"slug":"car-scenes","history":true}')
echo "$got" | grep -q '"versions"' && ok "History lists a board's earlier copies" || no "History lists a board's earlier copies" "$got"
before=$(mcall 140 board '{"slug":"car-scenes"}' | grep -c '"id":')
mcall 141 set_board "{\"slug\":\"car-scenes\",\"remove\":[\"$IDEA\",\"$GEAR\",\"$NOTE\",\"$STILL\"]}" >/dev/null
got=$(mcall 142 set_board '{"slug":"car-scenes","restore":"latest"}')
after=$(mcall 143 board '{"slug":"car-scenes"}' | grep -c '"id":')
echo "$got" | grep -q 'put back' && [ "$before" = "$after" ] \
  && ok "…and restore puts the latest back" || no "…and restore puts the latest back" "$before then $after: $got"
got=$(mcall 144 set_board '{"slug":"car-scenes","rename":"Car Nights"}')
echo "$got" | grep -q 'renamed Car Nights' && mcall 145 boards '{}' | grep -q '"board": "Car Nights"' \
  && mcall 146 boards '{}' | grep -q '"slug": "car-scenes"' \
  && ok "a board is renamed, and keeps its address" || no "a board is renamed, and keeps its address" "$got"
CNAME=$(body "$H/f/$FILM/car-scenes?as=$OWNER" | grep -o 'data-bd="car-scenes-[0-9a-f]*"' | head -1 | cut -d'"' -f2)
got=$(mcall 147 set_board '{"slug":"car-scenes","link_edit":true}')
echo "$got" | grep -q 'with the link may change it' && body "$H/f/$FILM/api/board/$CNAME/settings?as=$OWNER" | grep -q '"publicEdit":true' \
  && ok "he lets link visitors edit, from a chat" || no "he lets link visitors edit, from a chat" "$got"
got=$(mcall 148 board "{\"slug\":\"car-scenes\",\"look\":[\"$STILL\"]}")
tell "{\"jsonrpc\":\"2.0\",\"id\":149,\"method\":\"tools/call\",\"params\":{\"name\":\"board\",\"arguments\":{\"slug\":\"car-scenes\",\"look\":[\"$STILL\"]}}}" | grep -q '"type":"image"' \
  && ok "look sends a card's picture itself" || no "look sends a card's picture itself" "$got"
got=$(mcall 150 set_board "{\"slug\":\"car-scenes\",\"to_shot\":[{\"id\":\"$STILL\",\"shot\":\"33A\"}]}")
echo "$got" | grep -Eq 'Added to Shot 33A|already has it' && ok "Add to Shot from a chat, through the board's own door" || no "Add to Shot from a chat, through the board's own door" "$got"
got=$(mcall 151 boards '{"from_the_film":"scenes"}')
echo "$got" | grep -q '"scene": "33"' && ok "from_the_film lists what the board's panel offers" || no "from_the_film lists what the board's panel offers" "$got"

# Halcyon's board: a published page, its cards in the page, its two sorts
# (LEGACY_SORTS, obs and cam) — read, arranged, sorted and labelled over the
# MCP without anything moving where Halcyon's page keeps it.
mcall 152 set_page '{"name":"Old Look","markdown":"words"}' >/dev/null
cat > "$STATE/old-look.html" <<'HTML'
<section class="bd" data-bd="old-look-board" data-nolook>
<article class="bd-n" id="ycse" data-kind="ref" data-x="-600" data-y="-200" data-obs="0.9" data-cam="mini"><p class="bd-k">A24 · 2026</p><h3>You Can See Everything</h3></article>
<article class="bd-n" id="obsv" data-kind="idea" data-x="200" data-y="0" data-obs="0.2" data-cam="fx6"><h3>Observe</h3></article>
<article class="bd-n" id="hand" data-kind="gear" data-x="600" data-y="100" data-cam=""><h3>Handheld</h3></article>
<ol class="bd-ties"><li data-a="ycse" data-b="obsv">the purest version</li></ol>
</section>
HTML
put "p/$FILM/pages/old-look.html" "$STATE/old-look.html"
got=$(mcall 153 board '{"slug":"old-look"}')
echo "$got" | grep -q '"name": "Observe ↔ Move"' && echo "$got" | grep -q '"A-cam / B-cam": "A-cam"' && echo "$got" | grep -q '"label": "the purest version"' \
  && ok "Halcyon's published board still reads, sorts and threads" || no "Halcyon's published board still reads, sorts and threads" "$got"
got=$(mcall 154 arrange_board '{"slug":"old-look","by":"sort","sort":"A-cam / B-cam"}')
echo "$got" | grep -q 'A-cam (1)' && echo "$got" | grep -q 'Undecided (1)' \
  && body "$H/f/$FILM/api/board/old-look-board?as=$OWNER" | grep -q '"free":{"' \
  && ok "…arranges by its camera columns, keeping moved places where Halcyon keeps them" || no "…arranges by its camera columns, keeping moved places where Halcyon keeps them" "$got"
mcall 155 set_board '{"slug":"old-look","values":[{"id":"hand","sort":"Observe ↔ Move","value":"Observe"}],"label":[{"a":"ycse","b":"obsv","label":"closest"}]}' >/dev/null
got=$(body "$H/f/$FILM/api/board/old-look-board?as=$OWNER")
echo "$got" | grep -q '"obs":{"hand":0.9}' && echo "$got" | grep -q '"labels":{"obsv~ycse":"closest"}' \
  && ok "…and its Observe ↔ Move and its thread labels are kept Halcyon's way" || no "…and its Observe ↔ Move and its thread labels are kept Halcyon's way" "$got"
got=$(mcall 156 arrange_board '{"slug":"old-look","by":"sort","sort":"Observe ↔ Move"}')
echo "$got" | grep -q 'along Observe ↔ Move' && mcall 157 board '{"slug":"old-look"}' | apart | grep -q '^apart' \
  && ok "…and spreads along its line with nothing overlapping" || no "…and spreads along its line with nothing overlapping" "$got"
got=$(mcall 160 set_board "{\"slug\":\"old-look\",\"collapse\":[\"ycse\",\"hand\"]}")
echo "$got" | grep -q '2 collapsed' && body "$H/f/$FILM/api/board/old-look-board?as=$OWNER" | grep -q '"folded":{"ycse":true,"hand":true}' \
  && mcall 161 board '{"slug":"old-look"}' | grep -q '"collapsed": true' \
  && ok "cards collapse to picture and name from a chat" || no "cards collapse to picture and name from a chat" "$got"
# A clip a chat files on a shot is owed a poster (only a browser can take its
# first frame); the board's GET says so to an editor, and filing one pays it.
CLIP64=$(printf 'not really a clip, but enough bytes to be kept as one on a board' | base64 | tr -d '\n')
got=$(mcall 162 set_board "{\"slug\":\"car-scenes\",\"add\":[{\"kind\":\"clip\",\"base64\":\"$CLIP64\",\"filename\":\"take.mp4\"}]}")
CLIPID=$(echo "$got" | grep -o 'clip-[a-z0-9]*' | head -1)
got=$(mcall 163 set_board "{\"slug\":\"car-scenes\",\"to_shot\":[{\"id\":\"$CLIPID\",\"shot\":\"33A\"}]}")
CNAME=$(body "$H/f/$FILM/car-scenes?as=$OWNER" | grep -o 'data-bd="car-scenes-[0-9a-f]*"' | head -1 | cut -d'"' -f2)
owed=$(body "$H/f/$FILM/api/board/$CNAME?as=$OWNER")
CLIPSRC=$(echo "$owed" | python3 -c "import sys,json;print(([p['src'] for p in json.load(sys.stdin).get('posters',[])] or [''])[0])" 2>/dev/null)
echo "$got" | grep -q 'poster picture is made' && [ -n "$CLIPSRC" ] && echo "$owed" | grep -q '"shot":"33A"' \
  && ok "a clip filed from a chat is owed its poster, and the board is told" || no "a clip filed from a chat is owed its poster, and the board is told" "$got / $owed"
body "$H/f/$FILM/api/board/$CNAME?as=$DIRECTOR" | grep -q '"posters"' \
  && no "…and nobody the board is closed to hears of it" "told the crew" || ok "…and nobody the board is closed to hears of it"
psrc=$(curl -s -X PUT -H 'content-type: image/jpeg' --data-binary "@$STATE/board.png" "$H/f/$FILM/api/board/$CNAME/upload?name=poster.jpg&as=$OWNER" | python3 -c "import sys,json;print(json.load(sys.stdin).get('src',''))" 2>/dev/null)
body -X POST -H 'content-type: application/json' -d "{\"src\":\"$CLIPSRC\",\"shot\":\"33A\",\"poster\":\"$psrc\"}" "$H/f/$FILM/api/board/$CNAME/attach?as=$OWNER" >/dev/null
f=${CLIPSRC#pic/}
[ "$(code "$H/f/$FILM/media/${f%%.*}.jpg?as=$OWNER")" = 200 ] \
  && [ "$(body "$H/f/$FILM/api/board/$CNAME?as=$OWNER" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('posters',[])))" 2>/dev/null)" = 0 ] \
  && ok "…and the board filing its poster pays it" || no "…and the board filing its poster pays it" "still owed"
# A file sent as itself may be bigger than the 1 MB a message used to be held
# to — which refused anything over about 750 KB, add_document's too.
python3 -c "
import json, base64, os, sys
b = base64.b64encode(os.urandom(1_500_000)).decode()
json.dump({'jsonrpc': '2.0', 'id': 164, 'method': 'tools/call', 'params': {'name': 'set_board', 'arguments': {'slug': 'car-scenes', 'add': [{'kind': 'still', 'base64': b, 'filename': 'big.jpg'}]}}}, open(sys.argv[1], 'w'))" "$STATE/big.json"
got=$(said "$(asmcp -X POST "$H/mcp" -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' --data-binary "@$STATE/big.json")")
echo "$got" | grep -q '1 card added' && ok "a 1.5 MB picture sent as itself goes on" || no "a 1.5 MB picture sent as itself goes on" "$got"
# The day on a day card is written the same by the MCP and the page, or every
# day card a chat makes is rewritten when a board opens.
[ "$(sed -n '/^function dayWords/,/^}/p' "$HERE/src/boards.js")" = "$(sed -n '/^function dayWords/,/^}/p' "$HERE/public/board.js")" ] \
  && [ -n "$(sed -n '/^function dayWords/,/^}/p' "$HERE/src/boards.js")" ] \
  && ok "a day card's date is written the same by a chat and by the page" || no "a day card's date is written the same by a chat and by the page" "dayWords differs"
got=$(mcall 158 remove_page '{"slug":"car-scenes"}')
echo "$got" | grep -q 'is off' && ! mcall 159 boards '{}' | grep -q '"slug": "car-scenes"' \
  && ok "remove_page takes a board off the film" || no "remove_page takes a board off the film" "$got"

# Diagram mode through the web connector (`mcp/src/server/diagram.rs`, and
# `diagramPicture` / `layRoom` in src/mcp.js). His ask, 2026-09-30: "build out
# a mcp for diagram mode".
mcall 170 add_scene '{"number":"91"}' >/dev/null
got=$(mcall 171 edit_diagram '{"scene":"91","op":{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0},{"kind":"cast","cast":"ANNA","x":2,"y":1.5},{"kind":"light","x":3,"y":2.5,"rot":225}]}}')
echo "$got" | grep -q 'holds 3' && mcall 172 diagram_scenes '{}' | grep -q '"scene":"91"' \
  && ok "a plan drawn from a chat is listed among the scenes with one" || no "a plan drawn from a chat is listed among the scenes with one" "$got"
mcall 173 diagram_guide '{}' | grep -q 'STEPS (his ruling' && ok "the diagram guide is there to read" || no "the diagram guide is there to read" "no guide"
LIGHT=$(mcall 174 diagram '{"scene":"91"}' | python3 -c "import sys,json;print([e['id'] for e in json.load(sys.stdin)['els'] if e['kind']=='light'][0])" 2>/dev/null)
got=$(mcall 175 set_diagram_favorite "{\"scene\":\"91\",\"slot\":9,\"id\":\"$LIGHT\"}")
echo "$got" | grep -q 'Favorite 9 is' && mcall 176 place_favorite '{"scene":"91","slot":9,"x":1,"y":1}' | grep -q '^Made' \
  && ok "a favorite is kept and placed from a chat" || no "a favorite is kept and placed from a chat" "$got"
mcall 177 set_diagram_favorite '{"scene":"91","slot":9}' >/dev/null
got=$(mcall 178 room_scans '{"scene":"91"}')
echo "$got" | grep -q 'not shot at any location' && ok "room_scans says when a scene has no place" || no "room_scans says when a scene has no place" "$got"
pic=$(tell '{"jsonrpc":"2.0","id":179,"method":"tools/call","params":{"name":"diagram_picture","arguments":{"scene":"91","width":600}}}')
if printf '%s' "$pic" | grep -q '"type":"image"'; then
  printf '%s' "$pic" | python3 -c "import sys,json,base64;d=json.load(sys.stdin)['result']['content'][0]['data'];open(sys.argv[1],'wb').write(base64.b64decode(d))" "$STATE/plan.png"
  # `LC_ALL=C`: a PNG starts with the byte 0x89, which grep in a UTF-8 locale
  # reads as broken text and never matches, whatever the picture is.
  head -c 4 "$STATE/plan.png" | LC_ALL=C grep -q PNG && ok "diagram_picture hands Claude the plan as a PNG" || no "diagram_picture hands Claude the plan as a PNG" "not a PNG"
  [ -n "${KEEP_PLAN:-}" ] && cp "$STATE/plan.png" "$KEEP_PLAN"
else
  no "diagram_picture hands Claude the plan as a PNG" "$(printf '%s' "$pic" | head -c 300)"
fi

# ---- a film's changes never land in a portal (SL-1376) ----------------------
# 2026-10-01: a chat used the connector on Halcyon, a portal with no film,
# and wrote two change logs into it. The shelf and the rail counted the logs
# and called it a film, so they sent him to Schedule; the screens' own gate
# looked at the mark and answered "No such page"; the relay offered it to
# every Mac as a film. Now the connector refuses, and if logs land there
# anyway every door asks the one rule (`relay/portal.js`) and agrees it is a
# portal. Last in the run because it leaves the connector on the portal.
SPORTAL="13760000000000000000000000000001"
body -X PUT "${CONSOLE[@]}" -d '{"title":"Lone Portal","by":"console"}' "$H/console/$SPORTAL/portal" >/dev/null
printf '{"version":1,"status":"Active","shoot":{"start":"2099-03-01","end":"2099-03-02"}}' > "$STATE/lone-front.json"
put "p/$SPORTAL/front.json" "$STATE/lone-front.json"
got=$(mcall 180 projects '{}')
echo "$got" | python3 -c "import sys,json; r=[x for x in json.load(sys.stdin) if x['project']=='Lone Portal']; assert len(r)==1 and r[0]['studio']=='none yet, only its portal' and 'changes' not in r[0]" \
  && ok "projects calls a portal a portal" || no "projects calls a portal a portal" "$got"
got=$(mcall 181 open_project '{"film":"Lone Portal"}')
echo "$got" | grep -q "It is a portal with no Studio side yet" && ok "…and opening one says so, not an empty film's summary" || no "…and opening one says so, not an empty film's summary" "$got"
got=$(mcall 182 add_scene '{"number":"1"}')
echo "$got" | grep -qF 'Lone Portal has no Studio side yet, only its portal. Use set_page for a portal page, or turn a mode on with `modes` to make its Studio side.' \
  && ok "a film's tool on a portal is refused, in plain words" || no "a film's tool on a portal is refused, in plain words" "$got"
mcall 183 scenes '{}' | grep -q "no Studio side yet" && ok "…reading too, so an empty film never reads as an invitation" || no "…reading too, so an empty film never reads as an invitation" "answered"
mcall 184 set_page '{"name":"Prep","markdown":"Call sheet soon."}' | grep -q "your-domain.example" \
  && ok "…while its pages are still written" || no "…while its pages are still written" "refused"
! body "${CONSOLE[@]}" "$H/console/$SPORTAL" | grep -q '"stray_logs"' && ok "…and nothing was written into it as a film" || no "…and nothing was written into it as a film" "a log landed"

# Now the logs land anyway: a whole film's worth, the way Halcyon got two.
NLOGS=0
for log in "$ROOT"/studio/fixtures/Daybreak.shotlist/changes/*.log; do
  put "p/$SPORTAL/logs/$(basename "$log")" "$log"; NLOGS=$((NLOGS + 1))
done
page=$(body "$H/f/$SPORTAL?as=$OWNER")
[ "$(code "$H/f/$SPORTAL?as=$OWNER")" = 200 ] && ! echo "$page" | grep -q 'data-key="schedule"' && ! echo "$page" | grep -q 'data-key="shotlist"' \
  && ok "stray logs under a portal leave its rail a portal's" || no "stray logs under a portal leave its rail a portal's" "rail offers the film's screens"
rows=$(echo "$page" | grep -o 'class="to[^"]*" data-key="[^"]*"[^>]*href="[^"]*"' | sed 's/.*href="\([^"]*\)".*/\1/' | sort -u)
bad=""; n=0
for r in $rows; do n=$((n + 1)); c=$(code "$H$r?as=$OWNER"); [ "$c" = 200 ] || bad="$bad $r=$c"; done
[ "$n" -gt 0 ] && [ -z "$bad" ] && ok "…and every row it offers opens ($n)" || no "…and every row it offers opens" "${bad:-no rows found}"
[ "$(code "$H/f/$SPORTAL/schedule?as=$OWNER")" = 404 ] && ok "…while Schedule, which it does not offer, is nothing" || no "…while Schedule, which it does not offer, is nothing" "$(code "$H/f/$SPORTAL/schedule?as=$OWNER")"
[ "$(body "$H/f/$SPORTAL/api/state?as=$OWNER")" = '{"logs":[]}' ] && ok "…and its pages are handed no logs to replay" || no "…and its pages are handed no logs to replay" "$(body "$H/f/$SPORTAL/api/state?as=$OWNER" | head -c 120)"
got=$(body "${CONSOLE[@]}" "$H/console/$SPORTAL")
echo "$got" | grep -q '"portal":true' && echo "$got" | grep -q "\"stray_logs\":$NLOGS" && echo "$got" | grep -q '"warning":"' \
  && ok "the console's readout still says portal, and warns of the strays" || no "the console's readout still says portal, and warns of the strays" "$(echo "$got" | head -c 300)"
mcall 185 projects '{}' | grep -q '"studio": "none yet, only its portal"' && ok "…and so does projects" || no "…and so does projects" "called a film"
mcall 186 add_shot '{"scene":"33","description":"Into a portal"}' | grep -q "no Studio side yet" \
  && ok "…and a chat still cannot add to it" || no "…and a chat still cannot add to it" "added"
# The one place every write goes through (`keep`): the portal's own Diagrams
# page, on a scene the strays do hold, so the engine really makes the edit.
got=$(body -X PUT -H 'content-type: application/json' -d '{"scene":"33","ops":[{"op":{"op":"add","els":[{"kind":"wall","x":0,"y":0,"x2":4,"y2":0}]}}]}' "$H/f/$SPORTAL/api/diagram?as=$OWNER")
echo "$got" | grep -q "no Studio side yet" && ok "…nor a plan drawn on the portal itself" || no "…nor a plan drawn on the portal itself" "$(echo "$got" | head -c 200)"
[ "$(body "${CONSOLE[@]}" "$H/console/$SPORTAL" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("stray_logs",0))' 2>/dev/null)" = "$NLOGS" ] \
  && ok "…and not one more log landed" || no "…and not one more log landed" "count changed"

# ---- view links (Ref 1421) ----------------------------------------------------
# **A filtered Shot List, shared on its own.** The holder is handed the shots
# the filter keeps and nothing else of the film — cut by the server, so every
# other address, the change logs and the lists are refused at the door.
SHAREV="share.your-domain.example:$PORT"
VJ="$STATE/viewjar"
made=$(body -X POST -H 'content-type: application/json' -d '{"name":"Stunt Shots","facets":[["tags","Stunt"]]}' "$H/f/$FILM/api/views?as=$OWNER")
vpath=$(echo "$made" | python3 -c 'import json,sys;print(json.load(sys.stdin)["made"]["path"])' 2>/dev/null)
echo "$vpath" | grep -Eq '/v/stunt-shots-[a-z0-9]{8}$' && ok "he makes a view link from a filter" || no "he makes a view link from a filter" "$made"
curl -s -c "$VJ" -b "$VJ" -H "x-hub-host: $SHAREV" "$H$vpath" | grep -q '"lens":{' && ok "…and it opens on the share host" || no "…and it opens on the share host" "no page"
body -b "$VJ" -H "x-hub-host: $SHAREV" "$H/f/$FILM/api/view" | python3 -c '
import json,sys; m=json.load(sys.stdin); rows=[r for g in m["groups"] for r in g["rows"]]
sys.exit(0 if rows and all("Stunt" in r["tags"] for r in rows) and not m["locations"] and not m["boards"] and "driveFolder" not in m["project"] else 1)' \
  && ok "…handed only the Stunt shots, no locations, boards or folders" || no "…handed only the Stunt shots" "wider"
bad=""
for p in /shotlist /schedule /locations /api/state /api/people /api/views /share /people; do
  c=$(code -b "$VJ" -H "x-hub-host: $SHAREV" "$H/f/$FILM$p"); [ "$c" = 404 ] || bad="$bad $p=$c"
done
[ -z "$bad" ] && ok "…and refused every other address of the film" || no "…and refused every other address of the film" "$bad"
vcode=${vpath: -8}
body -X PUT -H 'content-type: application/json' -d "{\"code\":\"$vcode\",\"off\":true}" "$H/f/$FILM/api/views?as=$OWNER" >/dev/null
[ "$(code -b "$VJ" -H "x-hub-host: $SHAREV" "$H/f/$FILM/api/view")" = 404 ] && ok "switched off, the view opens nothing" || no "switched off, the view opens nothing" "still open"
mcall 189 open_project '{"film":"Daybreak"}' >/dev/null
got=$(mcall 190 share_view '{"name":"Free Driving","filters":[{"field":"Tags","value":"free driving"}]}')
echo "$got" | grep -Eq "Free Driving: 1 shot of .*/v/free-driving-[a-z0-9]{8}" && ok "an AI makes a view link" || no "an AI makes a view link" "$got"
body -X DELETE -H 'content-type: application/json' -d "{\"code\":\"$vcode\"}" "$H/f/$FILM/api/views?as=$OWNER" >/dev/null
[ "$(code -H "x-hub-host: $SHAREV" "$H$vpath")" = 404 ] && ok "removed, its link is nothing" || no "removed, its link is nothing" "still answers"

# ---- the Library (2026-10-02) -------------------------------------------------
# His ask: the Library is the base where everything a film holds is kept, the
# sidebar is what he pins from it, Archive is a folder inside it, and it reads
# for everybody — public link or not. Nothing is deleted, nothing moves, and
# every page still opens from its address.
mcall 400 set_page '{"name":"Wrap Notes","markdown":"Done with this one."}' >/dev/null
rail() { body "$H/f/$FILM?as=$OWNER"; }
rail | grep -q 'data-key="wrap-notes"' \
  && ok "a page is on the sidebar to begin with" || no "a page is on the sidebar to begin with" "no row"
rail | grep -q 'class="to librow[^"]*"[^>]*href="[^"]*/library"' \
  && ok "the Library is a row on the sidebar, not a tool beside Add" || no "the Library is a row on the sidebar" "absent"
rail | grep -q 'class="railtool[^"]*"[^>]*/library' \
  && no "…and not among the tools" "it is" || ok "…and not among the tools"
body "$H/f/$EFILM?as=$DIRECTOR" | grep -q 'librow' \
  && ok "a reader has the Library on the sidebar too" || no "a reader has the Library on the sidebar too" "absent"
got=$(body "$H/f/$FILM/library?as=$OWNER")
# **His Library is Pages** (2026-10-11, the approved layout): a list, one card
# per category, each row one Shown switch and a ⋯ (Move To, Archive). Pinning
# and icons are the sidebar's, so they are not here.
echo "$got" | grep -q 'Wrap Notes' && echo "$got" | grep -q 'name="flip" value="sections:wrap-notes"' && echo "$got" | grep -q 'class="fh-lsw" role="switch"' \
  && ok "the Library lists every page, each with its one Shown switch" || no "the Library lists every page" "not listed"
! echo "$got" | grep -q 'me-sections\|>Pinned<i>\|>Private<i>\|name="sidebar"' \
  && ok "…and no Pinned, Private or Me in it" || no "…and no Pinned, Private or Me in it" "still there"
echo "$got" | python3 -c '
import sys
h=sys.stdin.read(); i=h.index("class=\"fh-lcat\" id=\"shelf-other\""); j=h.find("class=\"fh-lcat", i+10)
sys.exit(0 if "data-key=\"wrap-notes\"" in h[i:(j if j>0 else len(h))] else 1)' \
  && ok "…filed by what each thing is (Wrap Notes stands in Other)" || no "…filed by what each thing is" "not in Other"
echo "$got" | grep -q 'data-lfind' && echo "$got" | grep -q 'data-lfilter="hidden"' && echo "$got" | grep -q 'data-lcount' \
  && ok "…with a search, All and Hidden, and how many are shown" || no "…with a search, All and Hidden" "missing"
echo "$got" | grep -q 'class="fh-lchip">\(File\|Link\)' \
  && ok "…with the film's documents in it too" || no "…with the film's documents in it too" "no document row"
body "$H/f/$FILM/library?as=$VIEWER" | grep -q 'class="fh-cv page"' && body "$H/f/$FILM/library?as=$VIEWER" | grep -q 'class="fh-shelf" id="shelf-' \
  && ! body "$H/f/$FILM/library?as=$VIEWER" | grep -q 'fh-lpane' \
  && ok "…while a reader's Library is still shelves of covers" || no "…while a reader's Library is still shelves of covers" "changed"
# The categories can be put in order now (dragging headings, above), so the
# Library follows the film's own order rather than a fixed one.
body "$H/f/$FILM/library?part=pick&as=$OWNER" > /tmp/hubcheck-picks.json
echo "$got" | python3 -c '
import re,sys,json
h=sys.stdin.read()
ids=re.findall(r"class=\"fh-lcat\" id=\"shelf-([a-z0-9-]+)\"",h)
want=[s["id"] for s in json.load(open("/tmp/hubcheck-picks.json"))["shelves"]]
sys.exit(0 if ids and ids==want else 1)' \
  && ok "…the categories stand in his own order" || no "…the categories stand in his own order" "out of order"
echo "$got" | grep -q 'data-key="wrap-notes"[^>]*data-shelf="Other"' && echo "$got" | grep -q '<details class="fh-lfold" open>' \
  && ok "…each row knowing its category, the first category open" || no "…each row knowing its category, the first category open" "missing"
# a reader may open it and sees no controls
got=$(body "$H/f/$EFILM/library?as=$DIRECTOR")
[ "$(code "$H/f/$EFILM/library?as=$DIRECTOR")" = 200 ] && ! echo "$got" | grep -q 'name="sidebar"' && ! echo "$got" | grep -q 'name="flip"' \
  && ok "a reader opens the Library and gets no controls" || no "a reader opens the Library and gets no controls" "controls shown or refused"
[ "$(code -X POST "$H/f/$EFILM/library?as=$DIRECTOR" --data-urlencode "sidebar=bible" --data-urlencode "on=0")" = 403 ] \
  && ok "a reader cannot change it" || no "a reader cannot change it" "not 403"
# a page's own menu
body "$H/f/$FILM/wrap-notes?as=$OWNER" | grep -q '>Pinned<i>' && body "$H/f/$FILM/wrap-notes?as=$OWNER" | grep -q '>Archive<' \
  && ok "the page's own menu: Pinned and Archive" || no "the page's own menu" "absent"
body "$H/f/$EFILM/bible?as=$DIRECTOR" | grep -q '>Pinned<i>' \
  && no "…and a reader's menu has neither" "they have it" || ok "…and a reader's menu has neither"
[ "$(code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "sidebar=no-such-page" --data-urlencode "on=0")" = 404 ] \
  && ok "a page that is not there is refused" || no "a page that is not there is refused" "not 404"
# off the sidebar, still in the Library, still open
[ "$(code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "sidebar=wrap-notes" --data-urlencode "on=0")" = 303 ] \
  && ok "Take Off Sidebar answers" || no "Take Off Sidebar answers" "not 303"
rail | grep -q 'data-key="wrap-notes"' && no "a page taken off leaves the sidebar" "still there" || ok "a page taken off leaves the sidebar"
[ "$(code "$H/f/$FILM/wrap-notes?as=$OWNER")" = 200 ] && ok "…and still opens from its address" || no "…and still opens" "not 200"
body "$H/f/$FILM/library?as=$OWNER" | grep -q 'Wrap Notes' \
  && ok "…and is still in the Library" || no "…and is still in the Library" "gone"
# a drag only sends what is on screen
code -X POST "$H/f/$FILM/groups?as=$OWNER" --data-urlencode "new=Wrap" >/dev/null
code -X POST "$H/f/$FILM/order?as=$OWNER" --data-urlencode "group=Wrap
wrap-notes" --data-urlencode "group=
shotlist" >/dev/null
code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "sidebar=wrap-notes" --data-urlencode "on=0" >/dev/null
code -X POST "$H/f/$FILM/order?as=$OWNER" --data-urlencode "group=Wrap
" --data-urlencode "group=
shotlist" >/dev/null
code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "sidebar=wrap-notes" --data-urlencode "on=1" >/dev/null
got=$(rail)
head=$(printf '%s' "$got" | grep -bo '>Wrap<' | head -1 | cut -d: -f1)
row=$(printf '%s' "$got" | grep -bo 'data-key="wrap-notes"' | head -1 | cut -d: -f1)
tail1=$(printf '%s' "$got" | grep -bo 'data-key="shotlist"' | head -1 | cut -d: -f1)
[ -n "$head" ] && [ -n "$row" ] && [ "$head" -lt "$row" ] && [ "$row" -lt "$tail1" ] \
  && ok "put back on the sidebar, a page returns under the heading it left" \
  || no "put back on the sidebar, a page returns under the heading it left" "Wrap=$head row=$row shotlist=$tail1"
# Archive is a folder inside the Library
[ "$(code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "archive=wrap-notes" --data-urlencode "on=1")" = 303 ] \
  && ok "Archive answers" || no "Archive answers" "not 303"
rail | grep -q 'data-key="wrap-notes"' && no "an archived page leaves the sidebar" "still there" || ok "an archived page leaves the sidebar"
got=$(body "$H/f/$FILM/library?as=$OWNER")
echo "$got" | grep -q 'id="shelf-archive"' && echo "$got" | grep -q 'name="archive" value="wrap-notes"' && echo "$got" | grep -q 'Unarchive' \
  && ok "…and sits in the Library's Archive, with Unarchive" || no "…and sits in the Archive" "not there"
[ "$(code "$H/f/$FILM/wrap-notes?as=$OWNER")" = 200 ] && ok "…and still opens from its address" || no "…and still opens" "not 200"
code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "archive=wrap-notes" --data-urlencode "on=0" >/dev/null
rail | grep -q 'data-key="wrap-notes"' \
  && ok "taken out of the Archive, it is back on the sidebar" || no "taken out of the Archive" "not back"
# visibility from the Library: the same switches the Visibility panel has
code -X POST "$H/f/$FILM/visibility?as=$OWNER" --data-urlencode "flip=sections:wrap-notes" --data-urlencode "back=library" >/dev/null
librow() { body "$H/f/$FILM/library?as=$OWNER" | python3 -c '
import sys
import re
h=sys.stdin.read(); k=sys.argv[1]; i=re.search(r"class=\"fh-lrow[^\"]*\"[^>]* data-key=\""+re.escape(k)+"\"", h).start(); j=h.find("class=\"fh-lrow", i+10)
print(h[i:(j if j>0 else len(h))])' "$1"; }
librow wrap-notes | grep -q 'role="switch" aria-checked="false"' \
  && ok "a Library switch makes a page private" || no "a Library switch makes a page private" "state not shown"
code -X POST "$H/f/$FILM/visibility?as=$OWNER" --data-urlencode "flip=sections:wrap-notes" --data-urlencode "back=library" >/dev/null
# Move To: shelves are filed by name, and a card can be moved
code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "shelf=wrap-notes" --data-urlencode "to=Technical" >/dev/null
got=$(body "$H/f/$FILM/library?as=$OWNER")
sec=$(printf '%s' "$got" | grep -bo 'id="shelf-technical"' | head -1 | cut -d: -f1)
card=$(printf '%s' "$got" | grep -bo 'data-find="wrap notes' | head -1 | cut -d: -f1)
nextsec=$(printf '%s' "$got" | grep -bo 'class="fh-lcat" id="shelf-' | awk -F: -v s="${sec:-0}" '$1>s{print $1; exit}')
[ -n "$sec" ] && [ -n "$card" ] && [ "$card" -gt "$sec" ] && { [ -z "$nextsec" ] || [ "$card" -lt "$nextsec" ]; } \
  && ok "Move To puts a page on another shelf" || no "Move To puts a page on another shelf" "technical=$sec card=$card next=$nextsec"
[ "$(code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode "shelf=wrap-notes" --data-urlencode "to=Nowhere")" = 404 ] \
  && ok "…and a shelf that is not there is refused" || no "…and a shelf that is not there is refused" "not 404"
[ "$(code -X POST "$H/f/$EFILM/library?as=$DIRECTOR" --data-urlencode "shelf=bible" --data-urlencode "to=Technical")" = 403 ] \
  && ok "…and a reader cannot move anything" || no "…and a reader cannot move anything" "not 403"
got=$(mcall 407 move_to_shelf '{"slug":"wrap-notes","shelf":"Other"}')
echo "$got" | grep -q "Other shelf" && ok "an AI moves a page back to its own shelf" || no "an AI moves a page back to its own shelf" "$got"
got=$(mcall 408 library '{}')
echo "$got" | grep -q '"shelf": "Other"' && ok "…and the Library says each page's shelf" || no "…and the Library says each page's shelf" "$got"
# Many at once: one post, one save, set rather than flip
got=$(body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes","no-such-page"],"action":"sidebar-off"}')
echo "$got" | grep -q '"changed":1' && echo "$got" | grep -q '"of":1' \
  && ok "a bulk change applies to the real keys and ignores the rest" || no "a bulk change applies to the real keys" "$got"
rail | grep -q 'data-key="wrap-notes"' && no "…and the page is off the sidebar" "still on" || ok "…and the page is off the sidebar"
got=$(body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"sidebar-off"}')
echo "$got" | grep -q '"ok":true' && ok "…and doing it twice is the same as once" || no "…and doing it twice is the same as once" "$got"
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"sidebar-on"}' >/dev/null
rail | grep -q 'data-key="wrap-notes"' && ok "…and back on, it returns" || no "…and back on, it returns" "gone"
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"archive"}' >/dev/null
body "$H/f/$FILM/library?as=$OWNER" | grep -q 'class="fh-lrow[^"]*"[^>]* data-key="wrap-notes"[^>]*data-archived="1"' \
  && ok "a bulk archive archives" || no "a bulk archive archives" "not archived"
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"unarchive"}' >/dev/null
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"shelf","to":"Technical"}' >/dev/null
body "$H/f/$FILM/library?as=$OWNER" | python3 -c '
import re,sys
h=sys.stdin.read()
i=h.index("id=\"shelf-technical\""); j=h.find("class=\"fh-lcat", i+10)
sys.exit(0 if "data-key=\"wrap-notes\"" in h[i:(j if j>0 else len(h))] else 1)' \
  && ok "a bulk move puts it on the shelf" || no "a bulk move puts it on the shelf" "not there"
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"shelf","to":"Other"}' >/dev/null
[ "$(code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"shelf","to":"Nowhere"}')" = 404 ] \
  && ok "a shelf that is not there is refused" || no "a shelf that is not there is refused" "not 404"
[ "$(code -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"delete"}')" = 400 ] \
  && ok "an action that does not exist is refused" || no "an action that does not exist is refused" "not 400"
[ "$(code -X POST "$H/f/$EFILM/library?as=$DIRECTOR" --data-urlencode 'bulk={"keys":["bible"],"action":"sidebar-off"}')" = 403 ] \
  && ok "a reader cannot change many either" || no "a reader cannot change many either" "not 403"
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"links-hide"}' >/dev/null
wn() { librow wrap-notes; }
wn | grep -q 'role="switch" aria-checked="false"' \
  && ok "a bulk Private is the same switch the panel has" || no "a bulk Private" "not private"
body -X POST "$H/f/$FILM/library?as=$OWNER" --data-urlencode 'bulk={"keys":["wrap-notes"],"action":"links-show"}' >/dev/null
wn | grep -q 'role="switch" aria-checked="false"' \
  && no "…and Public puts it back" "still private" || ok "…and Public puts it back"
# the connector does what the page does
got=$(mcall 401 set_on_sidebar '{"slug":"wrap-notes","pinned":false}')
echo "$got" | grep -q "unpinned" && ! rail | grep -q 'data-key="wrap-notes"' \
  && ok "an AI unpins a page" || no "an AI unpins a page" "$got"
got=$(mcall 402 library '{}')
echo "$got" | grep -q '"slug": "wrap-notes"' && echo "$got" | grep -q '"pinned": false' && echo "$got" | grep -q '"private": false' \
  && ok "…and reads the Library, with each page pinned or not, private or not" || no "…and reads the Library" "$got"
got=$(mcall 403 archive_page '{"slug":"wrap-notes","archived":true}')
echo "$got" | grep -q "unpinned and private" && ok "…and archives it, unpinned and private" || no "…and archives it" "$got"
mcall 402 library '{}' | python3 -c "import json,sys; v=json.load(sys.stdin)['pages']; p=[x for x in v if x['slug']=='wrap-notes'][0]; sys.exit(0 if p['archived'] and p['private'] and not p['pinned'] else 1)" \
  && ok "…and the Library says it is archived and private" || no "…and the Library says it is archived and private" "state"
[ "$(code "$H/f/$FILM/wrap-notes?as=$VIEWER")" != 200 ] \
  && ok "…and a viewer cannot open it" || no "…and a viewer cannot open it" "opened"
[ "$(code "$H/f/$FILM/wrap-notes?as=$DIRECTOR")" = 200 ] \
  && ok "…while an editor still can" || no "…while an editor still can" "refused"
got=$(mcall 404 archive_page '{"slug":"wrap-notes","archived":false}')
echo "$got" | grep -q "out of the Archive" \
  && ok "…and unarchives it to exactly what it was" || no "…and unarchives it to exactly what it was" "$got"
got=$(mcall 405 set_on_sidebar '{"slug":"wrap-notes","on":true}')
echo "$got" | grep -q "is pinned" && rail | grep -q 'data-key="wrap-notes"' \
  && ok "…and the older word on still pins it back" || no "…and the older word on still pins it back" "$got"
got=$(mcall 406 set_on_sidebar '{"slug":"nothing-here","on":false}')
echo "$got" | grep -qi "no page" && ok "…and is refused for a page that is not there" || no "…and is refused for a page that is not there" "$got"

# ---- the sidebar edited in place (moves 1, 2 and 4) ---------------------------
# Categories (the sidebar's headings), renames and where a new page lands are
# the same on the sidebar and for an AI: one tool each, and the portal's own
# post answers JSON for the Add menu.
got=$(mcall 420 edit_shelves '{"action":"add","name":"Gear"}')
echo "$got" | grep -q '"name": "Gear"' && rail | grep -q '<div class="grouphead"[^>]*>Gear</div>' \
  && ok "an AI adds a category, and the sidebar shows it" || no "an AI adds a category, and the sidebar shows it" "$got"
got=$(mcall 421 edit_shelves '{"action":"add","name":"gear"}')
echo "$got" | grep -qi "already a gear category" && ok "…and a category with the same name is refused" || no "…and a category with the same name is refused" "$got"
got=$(mcall 422 set_page '{"name":"Gear List","markdown":"Two cameras.","category":"Gear"}')
echo "$got" | grep -q "under Gear" && ok "an AI makes a page in a category" || no "an AI makes a page in a category" "$got"
got=$(rail)
under=$(printf '%s' "$got" | grep -bo '>Gear</div>' | head -1 | cut -d: -f1)
row=$(printf '%s' "$got" | grep -bo 'data-key="gear-list"' | head -1 | cut -d: -f1)
[ -n "$under" ] && [ -n "$row" ] && [ "$row" -gt "$under" ] && ok "…and the row is under that heading" || no "…and the row is under that heading" "heading=$under row=$row"
got=$(mcall 423 set_page '{"name":"Nowhere Page","markdown":"x","category":"No Such Category"}')
echo "$got" | grep -qi "no category called" && ok "…and an unknown category is refused before anything is written" || no "…and an unknown category is refused" "$got"
got=$(mcall 424 edit_shelves '{"action":"rename","shelf":"Gear","name":"Equipment"}')
echo "$got" | grep -q '"name": "Equipment"' && rail | grep -q '>Equipment</div>' && ! rail | grep -q '>Gear</div>' \
  && ok "an AI renames a category, and its pages go with it" || no "an AI renames a category" "$got"
got=$(mcall 425 rename_page '{"slug":"gear-list","name":"Camera Gear"}')
echo "$got" | grep -q "Camera Gear" && echo "$got" | grep -q "/camera-gear" && rail | grep -q '<span class="nm">Camera Gear</span>' \
  && [ "$(code "$H/f/$FILM/camera-gear?as=$OWNER")" = 200 ] && [ "$(code "$H/f/$FILM/gear-list?as=$OWNER")" = 301 ] \
  && ok "an AI renames a page, its address follows, the old one forwards" || no "an AI renames a page" "$got"
got=$(mcall 426 rename_page '{"slug":"camera-gear","name":"Wrap Notes"}')
echo "$got" | grep -qi "already a page" && ok "…and a name another page has is refused" || no "…and a name another page has is refused" "$got"
got=$(mcall 427 edit_shelves '{"action":"remove","shelf":"Equipment"}')
! rail | grep -q '>Equipment</div>' && rail | grep -q 'data-key="camera-gear"' \
  && ok "an AI removes a category and keeps its pages" || no "an AI removes a category and keeps its pages" "$got"

# Add's menu posts the same /add and asks for JSON.
add() { curl -s -X POST -H 'accept: application/json' "$@"; }
add_name=$(printf 'Lens Notes')
mcall 428 edit_shelves '{"action":"add","name":"Crew Notes"}' >/dev/null
got=$(add -F type=page -F "name=$add_name" -F "head=Crew Notes" "$H/f/$FILM/add?as=$OWNER")
echo "$got" | grep -q '"ok":true' && echo "$got" | grep -q '/lens-notes' \
  && ok "the Add menu's post answers JSON with where the page is" || no "the Add menu's post answers JSON" "$got"
got=$(rail)
under=$(printf '%s' "$got" | grep -bo '>Crew Notes</div>' | head -1 | cut -d: -f1)
row=$(printf '%s' "$got" | grep -bo 'data-key="lens-notes"' | head -1 | cut -d: -f1)
[ -n "$under" ] && [ -n "$row" ] && [ "$row" -gt "$under" ] && ok "…and a page added from a heading lands under it" || no "…and a page added from a heading lands under it" "heading=$under row=$row"
got=$(add -F type=page -F "name=$add_name" "$H/f/$FILM/add?as=$OWNER")
echo "$got" | grep -q '"ok":false' && echo "$got" | grep -qi "already a page" \
  && ok "…and a refusal is JSON too, with the reason" || no "…and a refusal is JSON too" "$got"
got=$(add -F type=link -F "name=Reference Clip" -F "url=https://vimeo.com/123" "$H/f/$FILM/add?as=$OWNER")
# A link is a page like any other since 2026-10-13: the answer is the Library,
# and the link is listed there and under Documents.
echo "$got" | grep -q '/library"' && body "$H/f/$FILM/documents?as=$OWNER" | grep -q "Reference Clip" \
  && body "$H/f/$FILM/library?as=$OWNER" | grep -q "Reference Clip" \
  && ok "…and a link is added to Documents" || no "…and a link is added to Documents" "$got"
[ "$(code -X POST -F type=page -F name=Sneaky "$H/f/$EFILM/add?as=$DIRECTOR")" = 403 ] \
  && ok "…and a reader cannot add" || no "…and a reader cannot add" "not 403"

# The sidebar and the Library say who sees what the same way.
code -X POST "$H/f/$FILM/visibility?as=$OWNER" --data-urlencode 'flip=sections:lens-notes' --data-urlencode 'back=lens-notes' >/dev/null
rail | grep -q 'class="to[^"]* offl"[^>]*data-key="lens-notes"[^>]*data-links="0"' \
  && ok "a private page has a lock on the sidebar, for him" || no "a private page has a lock on the sidebar" "no offl"
rail | grep -q 'data-key="lens-notes"[^>]*data-links="0"[^>]*data-rename="1"' \
  && ok "…and its row carries what its menu needs" || no "…and its row carries what its menu needs" "attributes"
body "$H/f/$EFILM?as=$DIRECTOR" | grep -q 'off-tag\|data-links\|data-arrange\|rowmore' \
  && no "…and a reader's sidebar carries none of it" "found" || ok "…and a reader's sidebar carries none of it"
librow lens-notes | grep -q 'fh-loff' && librow lens-notes | grep -q 'role="switch" aria-checked="false"' \
  && ok "the Library row says it is hidden: dimmed, its switch off" || no "the Library row says it is hidden" "not so"
body "$H/f/$FILM/library?as=$OWNER" | grep -q 'Hidden from Links\|Off Links\|Not on Sidebar' \
  && no "…and none of the old words are left" "still there" || ok "…and none of the old words are left"
rail | grep -q 'class="railphone"' \
  && no "the phone's own Add and Headings copies are retired" "still drawn" || ok "the phone's own Add and Headings copies are retired"
rail | grep -q 'class="filmmenu"' && rail | grep -q 'data-dock' && rail | grep -q 'data-dockfind' && rail | grep -q 'data-dockadd' \
  && ok "the sidebar has Find and a film menu, and the page has the phone's dock with Find and +" || no "the sidebar has a film menu and the page has the dock" "missing"
rail | grep -q 'class="railfind"' && rail | grep -q 'class="railadd"' \
  && ok "…and the foot's + and the top's Find" || no "…and the foot's + and the top's Find" "missing"

# Lens sets (2026-10-05): the portal reads a spec sheet's Lenses lines the
# way Projects Console does — the console's own cases, in lens-cases.json.
node "$HERE/lenses.mjs" >/dev/null 2>&1 \
  && ok "lens sets read the way the console reads them" || no "lens sets read the way the console reads them" "node hub/lenses.mjs"
node "$HERE/picks.mjs" >/dev/null 2>&1 \
  && ok "a spec sheet's lens sets break into picks" || no "a spec sheet's lens sets break into picks" "node hub/picks.mjs"
node "$HERE/entries.mjs" >/dev/null 2>&1 \
  && ok "cameras and LUTs read the way the console reads them" || no "cameras and LUTs read the way the console reads them" "node hub/entries.mjs"
# The Camera Spec Sheet on the project record (2026-10-14, src/specsheet.js):
# the move read against the ten real sheets, and a hub of its own on 8861.
# (Shared copy: the spec-sheet check ran against real Notion rows and was removed.)
# The camera page's LUTs and Notes drawn as Projects Console draws them
# (2026-10-14): rows of the table, a column per camera, held files said.
node "$HERE/specpage.mjs" >/dev/null 2>&1 \
  && ok "LUTs and Notes are rows of the sheet, as the console draws them" || no "LUTs and Notes on the camera page" "node hub/specpage.mjs"
node "$HERE/copyclick.mjs" >/dev/null 2>&1 \
  && ok "a link inside a copyable row opens; the rest of the row copies" || no "links inside copyable rows" "node hub/copyclick.mjs"
# Move Spec Sheets.app and Spec Sheet Switch.app (hub/spec-sheets.py): the
# helper against a fake of the four doors and a made-up password.
node "$HERE/specsheet-app.mjs" >/dev/null 2>&1 \
  && ok "Move Spec Sheets says the look, moves once, and flips the switch" || no "the spec sheet apps' helper" "node hub/specsheet-app.mjs"
# The refresh's Notion half (2026-10-17): only pages set up to follow Notion
# read it, by their own Notion page; nothing else on a card is asked about.
node "$HERE/refreshnotion.mjs" >/dev/null 2>&1 \
  && ok "the refresh reads Notion only for pages that follow it" || no "the refresh's Notion half" "node hub/refreshnotion.mjs"
# The studio's lens library and sensor modes (spec sheet phase 2,
# src/lenslibrary.js, src/sensormodes.js): seeds against the ten sheets, every
# change, the doors and the kit — its own hub on 8863.
# (Shared copy: the lens library check ran against real Notion rows and was removed.)

# A page that follows a Google Doc (2026-10-10): the portal's clock, the page
# menu's switch and the console's door, against a pretend Google, and the page
# drawn byte for byte as the Mac's Doc Mirror drew it. Its own hub, on 8797.
node "$HERE/portaldocs.mjs" >/dev/null 2>&1 \
  && ok "Drive files he switches on are the Documents page's, grouped, opened here" || no "Drive files on the Documents page" "node hub/portaldocs.mjs"
node "$HERE/syncmark.mjs" >/dev/null 2>&1 \
  && ok "a page syncing from a document says so, to him; People are the record's" || no "the Synced from line and the record's People" "node hub/syncmark.mjs"
node "$HERE/docfollow.mjs" >/dev/null 2>&1 \
  && ok "a page follows its Google Doc, drawn as Doc Mirror drew it" || no "a page follows its Google Doc" "node hub/docfollow.mjs"

# The tidy of the sync server leaves what the portal's boards and pages show
# (2026-10-15): the hub names the pictures they lean on; Studio asks first.
node "$HERE/boardheld.mjs" >/dev/null 2>&1 \
  && ok "the portal says which pictures its boards lean on" || no "the portal's held pictures" "node hub/boardheld.mjs"
# Studio's Export on the server (2026-10-17): the Mac's sheet cut, its names,
# _v2 for a name already there, and presets read as the Export window reads them.
node "$HERE/exporting.mjs" >/dev/null 2>&1 \
  && ok "the connector's export cuts and names as Studio does" || no "the connector's export" "node hub/exporting.mjs"

# ---- the connector does what he does (mcp-parity, 2026-10-17) ----------------
# His ask: "make sure the mcp is up to date on everything and can do anything i
# can do". The portal's own new doors: a picture put on a shot from the web,
# Refresh from Notion, a Released project's date, credit and stills, Show on
# Portal, a shoot's dates and name, a link renamed, the short name and the
# Diagrams page's link switch. (The engine's new tools: mcp/tests/parity.rs.)
list=$(tell '{"jsonrpc":"2.0","id":60,"method":"tools/list"}')
printf '%s' "$list" | python3 -c "
import sys,json; t={x['name']:x for x in json.load(sys.stdin)['result']['tools']}
need={'add_picture','refresh_from_notion','released','set_released','portal_documents','show_on_portal','set_shoot','rename_record_link','move_to_shoot','rename_scan','rename_version','delete_version','document_page','settle_times'}
assert need <= set(t), need-set(t)
assert 'attach' not in t
assert 'frame_guides' in t['update_project']['description']
assert 'Schedule Remaining' in t['schedule_scene']['description']
assert 'Complete' in t['set_record']['inputSchema']['properties']['status']['description']" \
  && ok "the connector offers every new tool, and says what the app now does" || no "the connector offers every new tool, and says what the app now does" "missing or stale"
SHOT=$(use shots '{}' | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['number'])")
SCENE=$(use scenes '{}' | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['number'])")
PNG=$(python3 -c "
import base64,struct,zlib
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
raw=b''.join(b'\x00'+bytes([200,120,40])*16 for _ in range(9))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',16,9,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
print(base64.b64encode(png).decode())")
got=$(use add_picture "$(printf '{"shot":"%s","base64":"%s","filename":"parity.png","name":"Parity Still","caption":"From the web"}' "$SHOT" "$PNG")")
echo "$got" | grep -q "Added to Shot $SHOT" && use attachments "$(printf '{"shot":"%s"}' "$SHOT")" | grep -q '"name":"Parity Still.png"' \
  && ok "add_picture puts a picture on a shot from the web" || no "add_picture puts a picture on a shot from the web" "$got"
got=$(use add_picture "$(printf '{"shot":"%s","base64":"%s","filename":"parity.png"}' "$SHOT" "$PNG")")
echo "$got" | grep -q "already has it" && ok "…the same picture twice is one frame" || no "…the same picture twice is one frame" "$got"
FILE=$(python3 -c "import sys,base64,hashlib; print(hashlib.sha256(base64.b64decode(sys.argv[1])).hexdigest()[:32]+'.png')" "$PNG")
got=$(use add_picture "$(printf '{"scene":"%s","url":"pic/%s"}' "$SCENE" "$FILE")")
echo "$got" | grep -q "Added to Scene $SCENE" && ok "…and one the project holds goes on a scene by its name, fetching nothing" || no "…and one the project holds goes on a scene by its name, fetching nothing" "$got"
got=$(use add_picture "$(printf '{"shot":"%s","scene":"%s","url":"pic/%s"}' "$SHOT" "$SCENE" "$FILE")")
echo "$got" | grep -q "Name one owner" && ok "…one owner at a time" || no "…one owner at a time" "$got"
got=$(use update_attachment "$(printf '{"shot":"%s","attachment":"Parity Still","crop":{"x":0.25,"y":0.5,"scale":1.5}}' "$SHOT")")
use attachments "$(printf '{"shot":"%s"}' "$SHOT")" | grep -q '"crop":{"x":0.25,"y":0.5,"scale":1.5}' \
  && ok "update_attachment crops a picture without touching the file" || no "update_attachment crops a picture without touching the file" "$got"
use remove_attachment "$(printf '{"shot":"%s","attachment":"Parity Still"}' "$SHOT")" >/dev/null
use remove_attachment "$(printf '{"scene":"%s","attachment":"Parity Still"}' "$SCENE")" >/dev/null
# The film's card names its record again (the record checks above let it go).
set_front "$(printf '{"source":"notion:%s"}' "$PAGE")" >/dev/null
# Released: the date, the credit and which select is the key still are the
# record's; selects are his, picked from the showcase's stills (Drive).
putfact selects '["1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","1cccccccccccccccccccccccccccccccc"]' >/dev/null
got=$(use set_released '{"released_date":"2026-03-14","my_credit":"Director of Photography","key_still":"1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","featured":["1cccccccccccccccccccccccccccccccc","1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]}')
[ "$(fact released_date)" = 2026-03-14 ] && [ "$(fact my_credit)" = "Director of Photography" ] && [ "$(fact key_still)" = 1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ] \
  && [ "$(factby featured)" = "portal AI connector" ] \
  && ok "set_released writes the date, his credit, the key still and Featured" || no "set_released writes the date, his credit, the key still and Featured" "$got"
use released '{}' | python3 -c "
import sys,json; r=json.load(sys.stdin)
assert r['released_date']=='2026-03-14' and r['my_credit']=='Director of Photography'
assert r['key_still']['id']=='1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' and [f['id'] for f in r['featured']]==['1cccccccccccccccccccccccccccccccc','1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'] and r['featured_starred']" \
  && ok "…released reads it back" || no "…released reads it back" "$(use released '{}' | head -c 400)"
got=$(use set_released '{"key_still":"not-a-select"}')
echo "$got" | grep -q "is not one of the selects" && [ "$(fact key_still)" = 1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ] \
  && ok "…a key still must be one of his selects" || no "…a key still must be one of his selects" "$got"
got=$(use set_released '{"featured":["1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","1cccccccccccccccccccccccccccccccc","1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}')
echo "$got" | grep -q "Written" && fact featured | python3 -c "import sys,json; assert len(json.load(sys.stdin))==3" \
  && ok "…a still named twice in Featured is starred once" || no "…a still named twice in Featured is starred once" "$got"
for f in selects featured key_still released_date my_credit; do putfact "$f" 'null' >/dev/null; done
# Show on Portal reads the project's Drive folder; with none, it says so.
got=$(use portal_documents '{}')
echo "$got" | grep -q "no Drive folder\|no Drive sign-in" && ok "portal_documents says when there is no Drive folder to read" || no "portal_documents says when there is no Drive folder to read" "$got"
# A shoot's dates, name and notes: on the record at once, Notion after.
rows='[{"id":"1111111111111111111111111111aaaa","title":"Call Her Back — Shoot 1","label":"Shoot 1","n":1,"start":"2026-07-09","end":"","status":"Wrapped"},{"id":"2222222222222222222222222222bbbb","title":"Call Her Back — Shoot 2 · Malibu Pickup","label":"Shoot 2 · Malibu Pickup","n":2,"start":"2026-10-06","end":"","status":"Upcoming"}]'
putfact shoots "$rows" >/dev/null
got=$(use set_shoot '{"shoot":"2","start":"2026-10-08","end":"2026-10-09","notes":"Two days now."}')
fact shoot_edits | python3 -c "import sys,json; e=json.load(sys.stdin)['2222222222222222222222222222bbbb']['want']; assert e['start']=='2026-10-08' and e['end']=='2026-10-09' and e['notes']=='Two days now.'" \
  && ok "set_shoot changes a shoot's dates and notes on the record" || no "set_shoot changes a shoot's dates and notes on the record" "$got / $(fact shoot_edits)"
got=$(use set_shoot '{"shoot":"Malibu Pickup","start":"2026-10-10","seen":{"start":"2026-10-06"}}')
echo "$got" | grep -q "changed since you read it" && ok "…a shoot changed since it was read is not written over" || no "…a shoot changed since it was read is not written over" "$got"
got=$(use set_shoot '{"shoot":"Shoot 9","name":"x"}')
echo "$got" | grep -q "No shoot called" && ok "…and a shoot it does not have is refused, naming them" || no "…and a shoot it does not have is refused, naming them" "$got"

# ---- add_shoot, set_shoot_crew and shoots (2026-10-19): Notion AI's way to add a
# shoot and set who is on it. The same server path as Add Shoot in Projects
# Console; two steps; his alone; shoots and crew live in the project record.
# The full Notion-up / Notion-down / token battery is hub/shoottools.mjs.
printf '%s' "$(tell '{"jsonrpc":"2.0","id":70,"method":"tools/list"}')" | python3 -c "
import sys,json; t={x['name']:x for x in json.load(sys.stdin)['result']['tools']}
assert {'add_shoot','set_shoot_crew','shoots'} <= set(t), set(t)
for n in ('add_shoot','set_shoot_crew','shoots'):
    d=t[n]['description']; assert 'project record' in d and 'does NOT reliably reach Studio' in d, n
assert 'SHOW HIM THAT PREVIEW' in t['add_shoot']['description']
assert 'add_shoot' in t['set_shoot']['description'] and 'project record' in t['set_shoot']['description']" \
  && ok "the connector offers add_shoot, set_shoot_crew and shoots, saying shoots live in the record" || no "the connector offers add_shoot, set_shoot_crew and shoots" "missing or unworded"
putfact shoots "$rows" >/dev/null
putfact crew '[{"person":"6c000000000000000000000000000001","name":"Dan Gaffer","roles":["Gaffer"],"shoots":["1111111111111111111111111111aaaa"],"all_shoots":true}]' >/dev/null
use shoots '{}' | python3 -c "
import sys,json; r=json.load(sys.stdin)
assert [s['label'] for s in r['shoots']]==['Shoot 1','Shoot 2 · Malibu Pickup'], r
assert all(s['crew'][0]['name']=='Dan Gaffer' and s['crew'][0]['on_all_shoots'] for s in r['shoots']), r" \
  && ok "shoots lists every shoot with its crew" || no "shoots lists every shoot with its crew" "$(use shoots '{}' | head -c 500)"
use record '{}' | python3 -c "
import sys,json; r=json.load(sys.stdin); assert all(s['crew'] for s in r['shoots']), r['shoots']" \
  && ok "…and so does record" || no "…and so does record" "$(use record '{}' | head -c 500)"
got=$(use add_shoot '{"start":"2026-11-03"}')
echo "$got" | grep -q "switched on" && ok "add_shoot says so plainly when Add Shoot isn't switched on for the server" || no "add_shoot when the server's Add Shoot is off" "$got"
got=$(use add_shoot '{"start":"2026-11-03","confirm":"0123456789abcdef0123456789abcdef0123"}')
echo "$got" | grep -q "isn't one I gave" && ok "…a confirm nobody gave is refused before anything is read" || no "…a confirm nobody gave is refused" "$got"
got=$(use add_shoot '{"start":"soon"}')
echo "$got" | grep -q "YYYY-MM-DD" && ok "…a day that isn't one is refused" || no "…a day that isn't one is refused" "$got"
got=$(said "$(dtell '{"jsonrpc":"2.0","id":71,"method":"tools/call","params":{"name":"add_shoot","arguments":{"start":"2026-11-03"}}}')")
echo "$got" | grep -q "Only Nathaniel" && ok "…and a collaborator is refused" || no "…and a collaborator is refused" "$got"
got=$(use set_shoot_crew '{"shoot":"Shoot 9","add":["Dan Gaffer"]}')
echo "$got" | grep -q "No shoot called" && ok "set_shoot_crew refuses a shoot the project doesn't have, naming its shoots" || no "set_shoot_crew with an unknown shoot" "$got"
got=$(use set_shoot_crew '{"shoot":"2","add":["Nobody Atall"]}')
echo "$got" | grep -qi "Notion\|isn't on this project" && ok "…and a person it can't find is refused, nothing written" || no "…and a person it can't find is refused" "$got"
putfact shoots '[]' >/dev/null; putfact crew '[]' >/dev/null
node --import "$HERE/nodehook.mjs" "$HERE/shoottools.mjs" 2>&1 | grep -v "Warning\|Reparsing\|To eliminate\|trace-warn" | tail -3 | grep -q "0 failed" \
  && ok "add_shoot's two steps, Notion down and the queue, and set_shoot_crew (hub/shoottools.mjs)" || no "add_shoot / set_shoot_crew battery" "node --import hub/nodehook.mjs hub/shoottools.mjs"
# Projects Console from the connector (2026-10-19): the confirm token's rules,
# the console's tools offered in his words, his alone, Link Edits' Undo, the
# portal's who-sees-what tools in two steps, and every list in tools/list
# typed. The end-to-end run on a stand-in Notion and Google is
# hub/mcpconsole-live.mjs (its own wrangler, PORT=<port>).
node --import "$HERE/nodehook.mjs" "$HERE/mcpconsole.mjs" 2>&1 | grep -v "Warning\|Reparsing\|To eliminate\|trace-warn" | tail -3 | grep -q " 0 failed" \
  && ok "the console's tools and the two steps (hub/mcpconsole.mjs)" || no "the console's tools and the two steps" "node --import hub/nodehook.mjs hub/mcpconsole.mjs"
# Complete (was Released) and Notion's waiting list in order, crew and documents waiting (2026-10-20).
node --import "$HERE/nodehook.mjs" "$HERE/completestage.mjs" 2>&1 | grep -v "Warning\|Reparsing\|To eliminate\|trace-warn" | tail -1 | grep -q " 0 failed" \
  && ok "Complete, and Notion's waiting list in order (hub/completestage.mjs)" || no "Complete battery" "node --import hub/nodehook.mjs hub/completestage.mjs"
node --import "$HERE/nodehook.mjs" "$HERE/shootkeep.mjs" 2>&1 | grep -v "Warning\|Reparsing\|To eliminate\|trace-warn" | tail -1 | grep -q " 0 failed" \
  && ok "shoots stay: the page and the list show the record's shoots when Notion cannot be read (hub/shootkeep.mjs)" || no "shoots-stay battery" "node --import hub/nodehook.mjs hub/shootkeep.mjs"
# (Shared copy: the New Shoot battery compared against his real Notion data and was removed.)
node --import "$HERE/nodehook.mjs" "$HERE/addshootspeed.mjs" 2>&1 | grep -v "Warning\|Reparsing\|To eliminate\|trace-warn" | tail -3 | grep -q " 0 failed" \
  && ok "Add Shoot's steps run side by side and in the right order (hub/addshootspeed.mjs)" || no "Add Shoot speed battery" "node --import hub/nodehook.mjs hub/addshootspeed.mjs"
putfact shoot_edits 'null' >/dev/null; putfact shoots '[]' >/dev/null
got=$(use add_record_link '{"slot":"watch","url":"https://vimeo.com/123456789","title":"Vimeo"}')
id=$(printf '%s' "$got" | sed -n 's/.*(id \([0-9a-f]*\)).*/\1/p')
got=$(use rename_record_link "$(printf '{"id":"%s","title":"The Film on Vimeo"}' "$id")")
fact links | grep -q '"title": "The Film on Vimeo"' && fact links | grep -q '"slot": "watch"' \
  && ok "a watch link is kept, and rename_record_link renames it" || no "a watch link is kept, and rename_record_link renames it" "$got / $(fact links | head -c 300)"
use remove_record_link "$(printf '{"id":"%s"}' "$id")" >/dev/null
got=$(use set_access '{"diagram_link_edit":true}')
use access '{}' | grep -q '"diagram_link_edit": true' && ok "set_access lets the link draw on the Diagrams page" || no "set_access lets the link draw on the Diagrams page" "$got"
use set_access '{"diagram_link_edit":false}' >/dev/null
use access '{}' | grep -q '"diagram_link_edit": false' && ok "…and stops it" || no "…and stops it" "$(use access '{}' | head -c 300)"
got=$(use set_access '{"short":"x"}')
echo "$got" | grep -q "2–24 letters" && ok "…a short name too short is refused" || no "…a short name too short is refused" "$got"
got=$(use refresh_from_notion '{}')
echo "$got" | grep -q "^ERROR\|Only he" && no "refresh_from_notion refreshes the portal from Notion" "$got" || ok "refresh_from_notion refreshes the portal from Notion"
got=$(said "$(dtell '{"jsonrpc":"2.0","id":62,"method":"tools/call","params":{"name":"refresh_from_notion","arguments":{}}}')")
echo "$got" | grep -q "Only he" && ok "…his alone" || no "…his alone" "$got"
set_front '{"source":""}' >/dev/null

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
