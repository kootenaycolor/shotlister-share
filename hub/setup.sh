#!/bin/bash
# Put the hub on his own Cloudflare account. **Run once, ever.**
#
# Reached by double-clicking "Set Up the Hub" at the top of the repo. Same shape
# as `relay/setup.sh`: everything is automatic except the one thing that cannot
# be — turning on Cloudflare's sign-in, which is a few clicks in their dashboard
# and cannot be done from a command.
#
# Safe to run again. Every step checks first and skips what is already done.

set -uo pipefail
cd "$(dirname "$0")"

# A double-clicked app gets none of his shell's path: no Homebrew, no Rust.
# Wrangler needs Node; the browser half needs cargo.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
oops() { printf '\n\033[31m%s\033[0m\n' "$1"; }
note() { printf '\033[2m%s\033[0m\n' "$1"; }

node_version=$(node --version 2>/dev/null | tr -d 'v' | cut -d. -f1)
if [ -z "$node_version" ] || [ "$node_version" -lt 22 ]; then
  oops "This needs Node 22 or newer and found ${node_version:-none}."
  echo "Install it with:  brew install node"
  exit 1
fi

# ---- 1. signed in? ----------------------------------------------------------
#
# `whoami` exits 0 whether or not he is signed in — the trap `relay/setup.sh`
# paid for on his machine. Read the words, not the exit code.
say "Checking whether you are signed in to Cloudflare…"
whoami_said=$(npx --yes wrangler@4 whoami 2>&1)
if echo "$whoami_said" | grep -qiE 'not authenticated|please run.*login|you are not'; then
  say "Opening Cloudflare in your browser."
  echo "Sign in, then come back to this window."
  npx --yes wrangler@4 login || { oops "That sign-in did not finish."; exit 1; }
else
  note "Already signed in."
fi

# ---- 3. the key the two halves sign notes with ------------------------------
#
# The MCP lives on `mcp.your-domain.example`, which has no Cloudflare
# sign-in in front of it — it cannot, or no AI could ever reach it. So when it
# needs to know who somebody is it sends their browser to the plain domain,
# which does have sign-in, and gets back a note saying who they are. This is
# what signs that note, so nobody can write their own.
#
# Made here and never shown, including to this script: it goes straight from
# openssl into wrangler.
say "Checking the MCP's signing key…"
if npx --yes wrangler@4 secret list 2>/dev/null | grep -q HUB_SECRET; then
  note "Already set."
else
  openssl rand -hex 32 | npx --yes wrangler@4 secret put HUB_SECRET \
    && note "Made a new one." \
    || { oops "Could not set the signing key."; exit 1; }
fi

# ---- 3b. the Projects Console's token ----------------------------------------
#
# The console takes a film's page down, flips its share link and hides its
# pages through `/console/…` on the hub (see `consoleDoor` in src/worker.js),
# with one token and no browser. **The same token the relay uses** — it is
# already in his Keychain as `shotlister-relay-token`, so the console carries
# one password, not two. Copied straight from the Keychain into wrangler and
# never printed.
say "Checking the console's token…"
if npx --yes wrangler@4 secret list 2>/dev/null | grep -q CONSOLE_TOKEN; then
  note "Already set."
elif relay=$(security find-generic-password -a shotlister-relay-token -w 2>/dev/null | tr -d '\n') && [ -n "$relay" ]; then
  printf '%s' "$relay" | npx --yes wrangler@4 secret put CONSOLE_TOKEN \
    && note "Set to the relay's token." \
    || { oops "Could not set the console's token."; exit 1; }
else
  note "No relay token in the Keychain yet — run Set Up Sync first, then this again. The hub works without it; only the console's door stays shut."
fi

# ---- 4. up it goes ----------------------------------------------------------
#
# **Through `deploy.sh`, the same road Deploy Shotlister takes**: it builds
# the browser half and stamps the commit. `--no-wait` because on a first run
# the address may not be routed yet; `--allow-dirty` because step 5 edits
# wrangler.toml and deploys again from the tree it just changed.
say "Putting the hub on Cloudflare…"
./deploy.sh --no-wait --allow-dirty || { oops "The deploy failed. Nothing was changed."; exit 1; }

# ---- 5. the one thing that is not automatic ---------------------------------
#
# Access applications are made in the Zero Trust dashboard. There is an API for
# it, but it needs a token with a scope the wrangler login does not grant — so
# asking for the two strings is honest where pretending to automate it would be
# a second sign-in flow to maintain.
team=$(grep -E '^ACCESS_TEAM' wrangler.toml | cut -d'"' -f2)
aud=$(grep -E '^ACCESS_AUD' wrangler.toml | cut -d'"' -f2)

if [ -n "$team" ] && [ -n "$aud" ]; then
  say "Sign-in is already set up. Nothing else to do."
  echo "The hub is at   https://your-domain.example"
  echo "For an AI, add  https://mcp.your-domain.example"
  exit 0
fi

say "One thing left, and it is clicking rather than typing."
cat <<'WORDS'

Cloudflare runs the sign-in, so nobody has to invent a password and you never
store one. It is free for up to fifty people.

In the browser window about to open:

  1. If it asks you to choose a team name, pick anything — it becomes part of
     an address only you ever see.
  2. Access  →  Applications  →  Add an application  →  Self-hosted.
  3. Call it "Shotlister hub". Its domain is  your-domain.example
  4. Add one policy: Allow, and for who it applies to choose "Everyone".

     That is deliberate and it is what means you never come back here. It
     lets anybody ask for a code, which only proves they can read the
     mailbox they typed. It does NOT let them see a film: somebody with no
     part in one gets an empty screen. Who sees what is set inside
     Shotlister, by inviting them — never here.
  5. When it is made, open it and copy two things:
       • the team name, from the address <team>.cloudflareaccess.com
       • the "Application Audience (AUD) Tag", a long string of letters

  ONE THING NOT TO DO, and it matters:

     Set the domain to  your-domain.example  and nothing else.
     Do NOT add an application for  mcp.your-domain.example.

     That address is the one an AI talks to, and a program cannot answer a
     sign-in page. It does its own asking, and it sends you here when it
     needs to know who you are. An application in front of it breaks every
     AI connected to it, and the way it breaks looks like nothing happening.

WORDS

open "https://one.dash.cloudflare.com/" 2>/dev/null
echo
read -r -p "Team name (just the name, not the whole address): " team
read -r -p "Application Audience (AUD) tag: " aud

if [ -z "$team" ] || [ -z "$aud" ]; then
  oops "Nothing entered, so nothing was changed."
  echo "The hub is up but nobody can sign in yet. Run this again when you have the two."
  exit 1
fi

python3 - "$team" "$aud" <<'PY'
import re, sys
team, aud = sys.argv[1], sys.argv[2]
p = "wrangler.toml"
s = open(p).read()
s = re.sub(r'^ACCESS_TEAM = ".*"$', f'ACCESS_TEAM = "{team}"', s, flags=re.M)
s = re.sub(r'^ACCESS_AUD = ".*"$', f'ACCESS_AUD = "{aud}"', s, flags=re.M)
open(p, "w").write(s)
PY

say "Putting it up again, now that it knows how to recognise people…"
./deploy.sh --no-wait --allow-dirty || { oops "That second deploy failed."; exit 1; }

say "Done."
echo "The hub is at   https://your-domain.example"
echo "For an AI, add  https://mcp.your-domain.example"
echo
note "You are an editor on every film without being on any list."
note "Who else may see what is set inside Shotlister — the ⚙ on a film's page."
echo
cat <<'WORDS'
To let Claude or ChatGPT work on your films, add

    https://mcp.your-domain.example

as a connector. It will send you to sign in the first time, show you what is
asking, and after you press Allow it can read and change any film you have a
part in — from your phone, from a laptop, from anywhere. Your Mac does not
have to be on.
WORDS
