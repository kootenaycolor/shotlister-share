#!/bin/bash
# **Launch the app over and over, and catch the one that does not come up.**
#
# The startup freeze of 2026-09-02: the window never finishes its first draw,
# one core goes flat out and memory climbs about a gigabyte a minute until the
# app is force-quit. It happened three times in ten minutes and then would not
# happen again — about a hundred and twenty launches, every posture that could
# be thought of, all clean. So this exists for the next time.
#
#   studio/soak.sh [runs]
#
# **Why the batteries cannot do this job.** Every flag in `quick.sh` and
# `checks.sh` makes a run a *checking* run, and a checking run reports and calls
# `exit(0)` before the window has settled. The freeze lives after that point, so
# no check can ever reach it. `SHOTLISTER_BACK=1` is the way in: a real launch,
# real window, real chrome — and it hands his screen straight back and quits
# itself at six seconds, saying what the chrome cost to settle.
#
# What each run prints:
#   a number  — how many times the two switchers had to rebuild. A settled
#               launch says a couple of dozen. Thousands means it is thrashing,
#               and that is worth reporting even if it did not tip over.
#   HUNG      — nothing printed and still alive: the freeze, caught. The stack
#               is written to /tmp, and the app writes its own copy to
#               ~/Library/Logs/Shotlister as well (see Watchdog.swift).
cd "$(dirname "$0")/.." || exit 1
APP="${SHOTLISTER_APP:-build/Shotlister Studio.app/Contents/MacOS/ShotlisterStudio}"
[ -x "$APP" ] || { echo "no app built — run studio/build.sh"; exit 1; }
RUNS="${1:-25}"

hung=0; ok=0
for i in $(seq 1 "$RUNS"); do
  said=$(mktemp)
  SHOTLISTER_BACK=1 "$APP" 2> "$said" > /dev/null &
  pid=$!
  waited=0
  while [ $waited -lt 20 ]; do
    sleep 1; waited=$((waited+1))
    kill -0 $pid 2>/dev/null || break
  done
  if kill -0 $pid 2>/dev/null; then
    hung=$((hung+1))
    where="/tmp/shotlister-froze-$i.txt"
    printf '\nrun %d: HUNG — one core at %s%%, %sk of memory\n' \
      "$i" "$(ps -o %cpu= -p $pid | tr -d ' ')" "$(ps -o rss= -p $pid | tr -d ' ')"
    sample $pid 3 -f "$where" >/dev/null 2>&1 && echo "        stack: $where"
    kill -9 $pid 2>/dev/null
  elif grep -q "froze" "$said"; then
    # It froze and the watchdog quit it — so the process is gone, but this is a
    # freeze, not a healthy launch. Without this the soak scores it as fine.
    hung=$((hung+1))
    printf '\nrun %d: FROZE — the app caught itself and quit\n' "$i"
    grep -o "wrote .*" "$said" | sed 's/^/        /'
  else
    ok=$((ok+1))
    printf '%s ' "$(grep -o 'switcher bodies: [0-9]*' "$said" | grep -o '[0-9]*$')"
  fi
  rm -f "$said"
done
printf '\n%d launches: %d came up, %d froze\n' "$RUNS" "$ok" "$hung"
[ "$hung" -gt 0 ] && echo "look in ~/Library/Logs/Shotlister too — the app photographed itself"
exit 0
