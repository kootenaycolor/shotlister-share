#!/bin/bash
# Put the hub up, stamped with the commit it came from.
#
# **The one deploy path**, the twin of `relay/deploy.sh`. Set Up the Hub calls
# it on the first day; Deploy Shotlister calls it every time after, second,
# because the hub reads what the relay stores and a change to a file format
# both know has to reach the server first. Its last line is the answer:
#
#     hub: 041bb8a live
#
#   hub/deploy.sh                build the browser half, deploy, wait for the live address
#   hub/deploy.sh --no-wait      deploy and stop — setup.sh does its own
#   hub/deploy.sh --allow-dirty  stamp and deploy an uncommitted tree (setup.sh, which
#                                edits wrangler.toml itself between two deploys)
#   DRY_RUN=1 hub/deploy.sh      build, bundle and stamp, deploy nothing — the battery
#
# **The stamp is the commit, and the tree has to be that commit.** The hub is
# built from six folders (`hub/`, `web/`, `mcpweb/`, `engine/`, `mcp/`,
# `storage/`) that three or four threads share; a half-written change in any
# of them going up under a clean hash is the fault the hub thread avoided by
# hand on 2026-09-10. An uncommitted change under any of them stops this with
# the file's name.

set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

# A double-clicked app gets none of his shell's path: no Homebrew, no Rust.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

# **The MCP's host, not the apex.** The apex has Cloudflare Access in front
# of it and answers a program with a sign-in page; `/version` is served on
# every host, so ask where nothing stands in the way — as the console does.
LIVE="https://mcp.your-domain.example/version"
SHIPS=(hub/ web/ mcpweb/ engine/ mcp/ storage/)
WAIT=yes
ALLOW_DIRTY=no
for arg in "$@"; do
  case "$arg" in
    --no-wait) WAIT=no ;;
    --allow-dirty) ALLOW_DIRTY=yes ;;
    *) echo "hub: unknown option $arg"; exit 2 ;;
  esac
done

oops() { printf '\033[31m%s\033[0m\n' "$1"; }

# ---- what is going up ---------------------------------------------------

commit=$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null)
[ -n "$commit" ] || { oops "hub: not in a git checkout, so there is no commit to stamp"; exit 1; }

dirty=$(git -C "$ROOT" status --porcelain -- "${SHIPS[@]}" 2>/dev/null)
if [ -n "$dirty" ]; then
  if [ "$ALLOW_DIRTY" = "yes" ]; then
    commit="$commit-dirty"
  else
    oops "hub: uncommitted changes in what the hub is built from — commit them or put them aside first"
    echo "$dirty" | sed 's/^/    /'
    exit 1
  fi
fi

branch=$(git -C "$ROOT" branch --show-current 2>/dev/null)
[ -n "$branch" ] && [ "$branch" != "main" ] && echo "hub: on branch $branch, not main"

# **Never put up less than is live.** 2026-10-02: a fast-forward of main
# failed, the deploy ran anyway from a branch that lacked the studio
# thread's live change, and the portal went back two minutes for everyone
# until it was merged and put up again. What is live must be in what goes
# up; merge main first. `HUB_BEHIND_OK=1` is the way past, on purpose only.
if [ "${DRY_RUN:-}" != "1" ] && [ "${HUB_BEHIND_OK:-}" != "1" ]; then
  live=$(curl -fsS -m 8 "$LIVE" 2>/dev/null | sed -n 's/.*"commit":"\([0-9a-f]\{7,\}\)".*/\1/p')
  if [ -n "$live" ] && ! git -C "$ROOT" merge-base --is-ancestor "$live" HEAD 2>/dev/null; then
    oops "hub: what is live ($live) is not in this checkout — merge main first, or another thread's work comes down"
    exit 1
  fi
fi

deployed=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- the browser half ---------------------------------------------------
#
# A failed build stops the deploy; the alternative is a hub put up with a
# stale `.wasm` from the last build, which is exactly what the battery once
# measured twenty-nine green ticks against.
echo "hub: building the browser half"
./build.sh || { oops "hub: the browser half would not build — nothing was deployed"; exit 1; }

# ---- up it goes ---------------------------------------------------------
W="./node_modules/.bin/wrangler"
[ -x "$W" ] || W="npx --yes wrangler@4"

args=(deploy --var "COMMIT:$commit" --var "DEPLOYED:$deployed")
if [ "${DRY_RUN:-}" = "1" ]; then
  out=$(mktemp -d)
  args+=(--dry-run --outdir "$out")
fi

said=$($W "${args[@]}" 2>&1)
status=$?
echo "$said" | grep -viE '^\s*$|wrangler 4|^─+$|telemetry'
if [ $status -ne 0 ]; then
  oops "hub: the deploy failed"
  exit 1
fi

if [ "${DRY_RUN:-}" = "1" ]; then
  rm -rf "$out"
  echo "hub: $commit bundled, not deployed"
  exit 0
fi
# The Film Set Objects pack the Diagrams page draws with (Ref 1216) — only
# when it changed. A failure here is said, not fatal: plans still draw, the
# pack's pieces are simply blank until the next deploy puts them up.
./fso.sh || oops "hub: the pack did not go up — plans will show blanks for its pieces"

[ "$WAIT" = "yes" ] || { echo "hub: $commit deployed"; exit 0; }

# ---- and is that what is answering? -------------------------------------
printf 'hub: waiting for %s' "${LIVE#https://}"
for _ in $(seq 1 24); do
  live=$(curl -sf -m 10 "$LIVE" 2>/dev/null | sed -nE 's/.*"commit":"([^"]*)".*/\1/p')
  if [ "$live" = "$commit" ]; then
    echo
    echo "hub: $commit live"
    exit 0
  fi
  printf '.'
  sleep 5
done
echo
oops "hub: deployed $commit, but the address still says ${live:-nothing} — run this again in a minute"
exit 1
