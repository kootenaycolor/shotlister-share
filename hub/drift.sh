#!/bin/bash
# How far the live workers are behind `main`, one line each.
#
#     relay: 041bb8a live, current
#     hub:   9b2c1de live, 3 commits behind main
#
# Reads what each worker says at its `/version` — the commit `deploy.sh`
# stamped on it — and counts the commits on `main` since. This is the
# systems map's amber box drawn by a program: the gap between "in the code"
# and "in the air" used to be found only by reading, which is how JPEG clip
# posters reached the Mac app a day before the hub that draws them.
#
#   hub/drift.sh          both workers
#   hub/drift.sh relay    one of them
#
# Exits 0 when both are current, 1 when either is behind or not answering.
# Needs the network and nothing else — no sign-in, no token: `/version`
# reveals a hash and a date. The hub is asked on the MCP's host because the
# apex has Access in front of it.

set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

worst=0

# **Against `main` as this checkout has it.** A thread on a branch sees what
# `main` here knows; `git fetch` first if the count matters to the minute.
head=$(git -C "$ROOT" rev-parse --short=7 main 2>/dev/null)
[ -n "$head" ] || { echo "no main branch here to compare with"; exit 1; }

look() { # look <name> <url>
  local name="$1" url="$2" said code live behind
  said=$(curl -s -m 15 -w '\n%{http_code}' "$url" 2>/dev/null)
  code=${said##*$'\n'}
  live=$(echo "$said" | sed -nE 's/.*"commit":"([^"]*)".*/\1/p')
  if [ "$code" = "404" ] || [ "$code" = "401" ]; then
    # A worker from before the route existed: up, and unable to say from what.
    # The relay answers an unknown path 401 rather than 404 — the token check comes first.
    printf '%-6s live, but has no /version yet — deploy once and it will\n' "$name:"
    worst=1; return
  fi
  if [ "$code" != "200" ]; then
    printf '%-6s not answering at %s (%s)\n' "$name:" "${url#https://}" "${code:-no reply}"
    worst=1; return
  fi
  if [ -z "$live" ] || [ "$live" = "unknown" ]; then
    printf '%-6s live, but no commit stamped — put up without deploy.sh; deploy once\n' "$name:"
    worst=1; return
  fi
  case "$live" in
    *-dirty)
      printf '%-6s %s live — deployed from an uncommitted tree, so nothing can say what it holds\n' "$name:" "$live"
      worst=1; return ;;
  esac
  if ! git -C "$ROOT" cat-file -e "$live^{commit}" 2>/dev/null; then
    printf '%-6s %s live — a commit this checkout does not have; git fetch and look again\n' "$name:" "$live"
    worst=1; return
  fi
  behind=$(git -C "$ROOT" rev-list --count "$live..main" 2>/dev/null)
  if [ "$behind" = "0" ]; then
    printf '%-6s %s live, current\n' "$name:" "$live"
  elif [ "$behind" = "1" ]; then
    printf '%-6s %s live, 1 commit behind main\n' "$name:" "$live"
    worst=1
  else
    printf '%-6s %s live, %s commits behind main\n' "$name:" "$live" "$behind"
    worst=1
  fi
  # Ahead of main happens too: a branch deployed, or main not yet pulled.
  local ahead
  ahead=$(git -C "$ROOT" rev-list --count "main..$live" 2>/dev/null)
  [ "${ahead:-0}" != "0" ] && printf '%-6s and %s commits main does not have\n' "" "$ahead"
}

# The batteries point these at a local worker; nothing else sets them.
RELAY_URL="${DRIFT_RELAY_URL:-https://sync.your-domain.example/v1/version}"
HUB_URL="${DRIFT_HUB_URL:-https://mcp.your-domain.example/version}"

which="${1:-both}"
case "$which" in
  relay|both) look relay "$RELAY_URL" ;;
esac
case "$which" in
  hub|both) look hub "$HUB_URL" ;;
esac
case "$which" in
  relay|hub|both) ;;
  *) echo "hub/drift.sh [relay|hub]"; exit 2 ;;
esac
exit $worst
