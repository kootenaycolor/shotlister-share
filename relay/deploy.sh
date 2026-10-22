#!/bin/bash
# Put the relay up, stamped with the commit it came from.
#
# **The one deploy path.** Set Up Sync calls this once, on the first day;
# Deploy Shotlister calls it every time after. Its last line is the answer:
#
#     relay: 041bb8a live
#
#   relay/deploy.sh              deploy, then wait until the live address says the commit
#   relay/deploy.sh --no-wait    deploy and stop — setup.sh does its own waiting
#   relay/deploy.sh --allow-dirty  stamp and deploy an uncommitted tree (setup.sh only)
#   DRY_RUN=1 relay/deploy.sh    bundle and stamp, deploy nothing — what the battery runs
#
# **The stamp is the commit, and the tree has to be that commit.** Three or
# four threads share this checkout, and one of them deploying another's
# half-written change is the fault the hub thread found by hand on 2026-09-10
# (it deployed from a clean copy of HEAD for that reason). So an uncommitted
# change under `relay/` stops this with the file's name, rather than going up
# under a hash that says it is something it is not.

set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

# A double-clicked app gets none of his shell's path.
export PATH="/opt/homebrew/bin:$PATH"

LIVE="https://sync.your-domain.example/v1/version"
WAIT=yes
ALLOW_DIRTY=no
for arg in "$@"; do
  case "$arg" in
    --no-wait) WAIT=no ;;
    --allow-dirty) ALLOW_DIRTY=yes ;;
    *) echo "relay: unknown option $arg"; exit 2 ;;
  esac
done

oops() { printf '\033[31m%s\033[0m\n' "$1"; }

# ---- what is going up ---------------------------------------------------

commit=$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null)
[ -n "$commit" ] || { oops "relay: not in a git checkout, so there is no commit to stamp"; exit 1; }

dirty=$(git -C "$ROOT" status --porcelain -- relay/ 2>/dev/null)
if [ -n "$dirty" ]; then
  if [ "$ALLOW_DIRTY" = "yes" ]; then
    commit="$commit-dirty"
  else
    oops "relay: uncommitted changes under relay/ — commit them or put them aside first"
    echo "$dirty" | sed 's/^/    /'
    exit 1
  fi
fi

branch=$(git -C "$ROOT" branch --show-current 2>/dev/null)
[ -n "$branch" ] && [ "$branch" != "main" ] && echo "relay: on branch $branch, not main"

deployed=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- up it goes ---------------------------------------------------------
#
# `--var` on a deploy sets a plain variable beside the ones in wrangler.toml
# and touches no secret. Wrangler from node_modules when it is there (the
# battery installs it); npx otherwise, so a fresh checkout still works.
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
  oops "relay: the deploy failed"
  exit 1
fi

if [ "${DRY_RUN:-}" = "1" ]; then
  rm -rf "$out"
  echo "relay: $commit bundled, not deployed"
  exit 0
fi
[ "$WAIT" = "yes" ] || { echo "relay: $commit deployed"; exit 0; }

# ---- and is that what is answering? -------------------------------------
#
# A Worker takes a moment to reach everywhere. Ask the live address until it
# says this commit, and say plainly if it never does — an old answer here is
# the gap between "in the code" and "in the air", which is the whole reason
# the stamp exists.
printf 'relay: waiting for %s' "${LIVE#https://}"
for _ in $(seq 1 24); do
  live=$(curl -sf -m 10 "$LIVE" 2>/dev/null | sed -nE 's/.*"commit":"([^"]*)".*/\1/p')
  if [ "$live" = "$commit" ]; then
    echo
    echo "relay: $commit live"
    exit 0
  fi
  printf '.'
  sleep 5
done
echo
oops "relay: deployed $commit, but the address still says ${live:-nothing} — run this again in a minute"
exit 1
