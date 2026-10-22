#!/bin/bash
# Two devices, a relay, and no shared folder anywhere.
#
#   remote/checks.sh
#
# Starts a real relay on this machine, runs the crate's own tests, then plays a
# day out across two project folders that can only reach each other through it.
# Nothing here touches the internet, his Cloudflare account, or his films.

set -uo pipefail
cd "$(dirname "$0")"

[ -x /opt/homebrew/bin/node ] && export PATH="/opt/homebrew/bin:$PATH"

PORT=${PORT:-8798}
export RELAY="http://127.0.0.1:$PORT"
export RELAY_TOKEN="checking-token-not-a-secret"
SCRATCH=$(mktemp -d)
started=$(date +%s)

# **Kill wrangler itself, not the thing holding the port.** 2026-08-31.
#
# `wrangler dev` runs the actual server in a child process called `workerd`, and
# it *puts a new one back* whenever the old one dies. So killing whatever holds
# the port achieves nothing — a second appears with a new pid — and killing the
# shell that launched it leaves wrangler orphaned onto init, still serving **the
# version of the script it started with**. The next run then finds the port
# answering, talks to a stale server, and fails in a way that reads exactly like
# a bug in the code.
#
# So: wrangler first, by its own command line, then the child. And a refusal to
# start at all if the port is somebody else's, because a check that quietly
# tests the wrong program is worse than one that will not run.
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


echo "── deciding what should move ──"
cargo test --quiet 2>&1 | grep -E 'test result|FAILED|panicked' || true
cargo test --quiet > /dev/null 2>&1 || { echo "the unit tests failed"; exit 1; }

echo
echo "── carrying it, for real ──"
echo "TOKEN=$RELAY_TOKEN" > ../relay/.dev.vars
(cd ../relay && npx --yes wrangler@4 dev \
  --port "$PORT" \
  --persist-to "$SCRATCH/state" \
  --inspector-port 0 \
  > "$SCRATCH/dev.log" 2>&1) &
DEV_PID=$!

printf 'starting the relay'
for _ in $(seq 1 60); do
  curl -sf "$RELAY/v1/health" > /dev/null 2>&1 && break
  printf '.'
  sleep 1
done
echo
if ! curl -sf "$RELAY/v1/health" > /dev/null 2>&1; then
  echo "the relay never came up. Its log:"
  tail -30 "$SCRATCH/dev.log"
  exit 1
fi

if ! cargo run --quiet --example two_devices_over_a_relay; then
  echo
  echo "────"
  echo "FAILED — two devices did not end up agreeing"
  exit 1
fi

# ---- tidying the folder must not jam the relay -------------------------
#
# Ref 192 folds settled logs into one, which rewrites a file the relay already
# has and deletes the others. Both halves fight the relay's own rules, and on
# 2026-09-04 that held an afternoon of his work on the Mac while the web drew
# the film as it had been at 5:14pm.
if ! cargo run --quiet --example a_fold_does_not_jam_the_relay; then
  echo
  echo "────"
  echo "FAILED — folding the old logs stopped the film reaching the relay"
  exit 1
fi

# ---- and then with a real film -----------------------------------------
#
# **A made-up film proves the rules; his own proves the assumptions.** This one
# found the thing worth finding: media is not one file per name — a clip is
# stored twice, and the still that stands for it does not hash to the name it
# is filed under. A synthetic test would never have had a video in it.
#
# The original is copied first and never written to.

FILM=${FILM:-ZED}
SOURCE="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister/$FILM.shotlist"
if [ ! -d "$SOURCE" ]; then
  echo
  echo "── a real film ── skipped, no $FILM.shotlist on this machine"
  echo "────"
  echo "passed, $(( $(date +%s) - started ))s"
  exit 0
fi

echo
echo "── a real film, there and back ──"
PID="00000000000000000000000000000777"
cp -R "$SOURCE" "$SCRATCH/film.shotlist"

there=$(cargo run --quiet --example sync_a_film -- \
  --path "$SCRATCH/film.shotlist" --project "$PID" --device aa01 | tail -1)
cargo run --quiet --example sync_a_film -- \
  --clone "$SCRATCH/back" --project "$PID" --device bb02 > /dev/null
back=$(cargo run --quiet --example sync_a_film -- \
  --path "$SCRATCH/back" --project "$PID" --device bb02 | tail -1)

echo "  sent:     $there"
echo "  came back: $back"

fail=0
[ "$there" = "$back" ] || { echo "  FAILED — the two devices do not hold the same film"; fail=1; }

# Every picture, byte for byte. The count matching is not the same as the bytes
# matching, and it is the bytes that get drawn.
for file in "$SCRATCH/film.shotlist/media/proxies"/*; do
  [ -e "$file" ] || break
  name=$(basename "$file")
  cmp -s "$file" "$SCRATCH/back/media/proxies/$name" || {
    echo "  FAILED — $name came back different"
    fail=1
  }
done

# **The full-size originals must stay put.** They are a cache of the biggest
# files in the project that every device currently drags down and none needs
# (Ref 332). Sending them would be this work quietly making that worse.
originals=$(ls "$SCRATCH/back/media/originals" 2>/dev/null | wc -l | tr -d ' ')
[ "$originals" = "0" ] || { echo "  FAILED — $originals original(s) travelled; only proxies should"; fail=1; }
echo "  originals left where they were: yes"

echo
echo "────"
if [ "$fail" -eq 0 ]; then
  echo "passed, $(( $(date +%s) - started ))s"
else
  echo "FAILED, $(( $(date +%s) - started ))s"
  exit 1
fi
