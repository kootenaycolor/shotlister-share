#!/bin/bash
# Put the relay on his own Cloudflare account. **Run once, ever.**
#
# Reached by double-clicking "Set Up Sync" at the top of the repo. Everything
# here is either automatic or a single sign-in in a browser window; nothing has
# to be typed, remembered, or pasted.
#
# It is safe to run again. Every step checks first and skips what is already
# done, so a run that was interrupted halfway can simply be repeated.

set -uo pipefail
cd "$(dirname "$0")"

# Wrangler wants Node 22 or newer. Homebrew's is current; nvm's older one
# usually shadows it in the path, which is why this is spelled out.
[ -x /opt/homebrew/bin/node ] && export PATH="/opt/homebrew/bin:$PATH"

BUCKET="shotlister"
SERVICE="shotlister-relay"
KEYCHAIN_ACCOUNT="shotlister-relay-token"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
oops() { printf '\n\033[31m%s\033[0m\n' "$1"; }

node_version=$(node --version 2>/dev/null | tr -d 'v' | cut -d. -f1)
if [ -z "$node_version" ] || [ "$node_version" -lt 22 ]; then
  oops "This needs Node 22 or newer and found ${node_version:-none}."
  echo "Install it with:  brew install node"
  exit 1
fi

# ---- 1. who he is -------------------------------------------------------
#
# **`whoami` exits 0 whether or not he is signed in.** It reports the bad news
# in words and calls that a successful run, so testing the exit code says
# "already signed in" for somebody who is not — and then the next command fails
# with something about a non-interactive environment, which is true and
# thoroughly unhelpful. 2026-08-31, on his machine, first run. Read the words.

say "Checking whether you are signed in to Cloudflare…"
whoami_said=$(npx --yes wrangler@4 whoami 2>&1)
if echo "$whoami_said" | grep -qiE 'not authenticated|please run.*login|you are not'; then
  say "Opening Cloudflare in your browser."
  echo "Sign in — or make an account, it is free — then come back to this window."
  echo
  # No redirection anywhere near this: it needs the terminal to talk to.
  if ! npx --yes wrangler@4 login; then
    oops "Signing in did not finish. Nothing has been changed."
    exit 1
  fi
  whoami_said=$(npx --yes wrangler@4 whoami 2>&1)
  if echo "$whoami_said" | grep -qiE 'not authenticated|please run.*login|you are not'; then
    oops "Still not signed in. Nothing has been changed."
    exit 1
  fi
fi
who=$(echo "$whoami_said" | grep -oiE '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' | head -1)
echo "Signed in${who:+ as $who}."

# ---- 2. somewhere to keep the films -------------------------------------

# **The exit code decides; the words only explain.** Matching on wording is
# how the first version of this file went wrong — a check that reads a message
# is a check that breaks the day the message is reworded. The one thing worth
# reading for is "already there", which is a success wearing a failure's code.
say "Making sure the storage bucket exists…"
bucket_said=$(npx --yes wrangler@4 r2 bucket create "$BUCKET" 2>&1)
if [ $? -eq 0 ]; then
  echo "Made the '$BUCKET' bucket."
elif echo "$bucket_said" | grep -qiE 'already (exists|owned)|10004'; then
  echo "The '$BUCKET' bucket was already there."
elif echo "$bucket_said" | grep -qiE 'enable R2|10042'; then
  # **A one-time switch on his account, not something a script may flip.**
  # Turning on a storage product means agreeing to its terms, which is his to
  # do and nobody else's. Say exactly where, rather than handing him an API
  # error and a shrug.
  account=$(echo "$bucket_said" | grep -oE '/accounts/[0-9a-f]{32}/' | head -1 | tr -d '/' | sed 's/accounts//')
  oops "R2 storage is not switched on for your Cloudflare account yet."
  echo
  echo "It is a one-time switch and only you can flip it — turning on a storage"
  echo "product means agreeing to its terms. Open this, click 'Enable R2' or"
  echo "'Purchase R2', then run this again:"
  echo
  if [ -n "$account" ]; then
    echo "    https://dash.cloudflare.com/$account/r2/overview"
  else
    echo "    https://dash.cloudflare.com/  →  R2 in the sidebar"
  fi
  echo
  echo "It may ask for a card. The free allowance is 10 GB and your three films"
  echo "are 127 MB, so this should not actually cost anything."
  exit 1
else
  oops "Could not make the storage bucket. Cloudflare said:"
  echo "$bucket_said" | grep -viE '^\s*$|wrangler 4|^─+$' | head -10
  exit 1
fi

# ---- 3. up it goes ------------------------------------------------------
#
# **Before the password, not after.** A secret belongs to a Worker, so setting
# one on a Worker that does not exist yet is an error — and deploying without
# it is safe, because a relay with no token refuses every single request.

# **Through `deploy.sh`, the same road Deploy Shotlister takes**, so the relay
# goes up stamped with its commit from the first day. `--no-wait` because the
# waiting below knows about a brand-new address; `--allow-dirty` because a
# first run is allowed to be from a tree with edits in it.
say "Putting the relay up…"
deploy=$(./deploy.sh --no-wait --allow-dirty 2>&1)
if [ $? -ne 0 ]; then
  oops "Putting it up did not work. Cloudflare said:"
  echo "$deploy" | grep -viE '^\s*$|wrangler 4|^─+$' | head -15
  exit 1
fi
echo "$deploy" | grep -viE 'warning|^\s*$' | tail -8

# ---- 4. the word that gets his devices in --------------------------------
#
# **Kept in the Keychain, not in a file.** A file in the repo is a file that
# gets committed, copied to another machine, or read over his shoulder; the
# Keychain is where a Mac already keeps this sort of thing.

say "Setting up the password your devices will use…"
token=$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$SERVICE" -w 2>/dev/null)
if [ -n "$token" ]; then
  echo "Found the existing one in your Keychain."
else
  token=$(openssl rand -hex 32)
  security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$SERVICE" -w "$token" -U 2>/dev/null \
    || { oops "Could not write to your Keychain."; exit 1; }
  echo "Made a new one and put it in your Keychain."
fi

secret_said=$(printf '%s' "$token" | npx --yes wrangler@4 secret put TOKEN 2>&1)
if [ $? -ne 0 ]; then
  oops "Could not give the relay its password. Cloudflare said:"
  echo "$secret_said" | grep -viE '^\s*$|wrangler 4|^─+$' | head -10
  exit 1
fi
echo "The relay knows it too."

url=$(echo "$deploy" | grep -oE 'https://[a-z0-9.-]*\.workers\.dev' | head -1)
if [ -z "$url" ]; then
  oops "It went up, but the address did not come back. Look above for it."
  exit 1
fi

# **The custom domain wins over the workers.dev one, whenever it answers.**
#
# Not a preference. `workers.dev` is on public blocklists — Workers get used for
# phishing, so filters blackhole the whole domain — and his own Pi-hole has
# refused it once already (Ref 471). The same lists run on hotel wifi and on set,
# which is exactly where a phone is meant to sync from.
#
# This was the gap that made Ref 472 only half true: the domain was registered
# and routed, and the address the apps read was still the workers.dev one,
# because this is the only place that writes it. A relay that works today on a
# blocklisted name is a relay that stops working on somebody else's network.
custom=$(grep -oE 'pattern[[:space:]]*=[[:space:]]*"[^"]+"' wrangler.toml \
  | head -1 | sed -E 's/.*"(.*)"/\1/')
if [ -n "$custom" ]; then
  printf 'Checking the %s address' "$custom"
  for _ in $(seq 1 12); do
    if curl -sf -m 10 "https://$custom/v1/health" 2>/dev/null | grep -q 'shotlister'; then
      url="https://$custom"
      break
    fi
    printf '.'
    sleep 5
  done
  echo
  if [ "$url" = "https://$custom" ]; then
    echo "Using $custom — a name that is yours and that filters do not block."
  else
    echo "$custom is not answering yet; using the workers.dev address for now."
    echo "Run this again later and it will move over on its own."
  fi
fi

# Where the apps look for it, so nothing has to be typed anywhere.
#
# The file is the one that matters — it is the folder the bridge already keeps
# its own things in, and anything headless can read it. The preference is a
# convenience for the Mac app, and its identifier is the real one from
# `studio/build.sh`, checked rather than guessed. (It was guessed first, and
# wrongly: `com.shotlister.studio`. A preference written under a name nothing
# reads fails completely silently, which is the worst way for this to be wrong.)
mkdir -p "$HOME/Library/Application Support/Shotlister"
echo "$url" > "$HOME/Library/Application Support/Shotlister/relay-url"
defaults write com.example.shotlister.studio RelayURL "$url" 2>/dev/null || true

# ---- 5. and does it answer? ---------------------------------------------
#
# Given a few tries: a Worker takes a moment to reach everywhere after a deploy,
# and a first run that says "it did not work" when it did is its own problem.

say "Checking it is really up…"
printf 'waiting for the address to work'
answered=no
for _ in $(seq 1 24); do
  if curl -sf -m 10 "$url/v1/health" 2>/dev/null | grep -q 'shotlister'; then
    answered=yes
    break
  fi
  printf '.'
  sleep 5
done
echo
if [ "$answered" = "no" ]; then
  # **Almost always the Mac's own DNS, not the relay.** A brand-new
  # workers.dev address does not exist for a minute or two after it is made,
  # and asking for it during that window teaches macOS that there is no such
  # host — which it then remembers for longer than this loop is willing to
  # wait. The relay is up; this machine simply cannot see it yet.
  #
  # So this must not read as a failure. Everything above it worked, and the
  # cure is to wait and run this again, not to undo anything.
  if ! dig +short "${url#https://}" 2>/dev/null | grep -q '[0-9]'; then
    oops "It is up, but this Mac cannot see its address yet."
    echo
    echo "That is normal for a brand-new address and nothing has gone wrong."
    echo "Wait five minutes and run this again — it will pick up where it left off."
  else
    oops "It is up and the address works, but it is not answering yet."
    echo
    echo "Give it a few minutes and run this again. If it keeps happening, open:"
    echo "  $url/v1/health"
  fi
  echo
  echo "Your relay: $url"
  exit 1
fi
echo "It answers."

# **The one check that actually matters.** Everything above can succeed on a
# relay that lets the whole internet read his films.
code=$(curl -s -o /dev/null -w '%{http_code}' "$url/v1/projects")
if [ "$code" = "401" ]; then
  echo "And it turns away anybody without the password, which is the point."
else
  oops "It answered a request with no password ($code) instead of refusing it."
  echo "Do not put films on it. Say so and this can be looked at."
  exit 1
fi

# And that the password itself works, so a first sync does not fail confusingly.
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$url/v1/projects")
if [ "$code" = "200" ]; then
  echo "And it lets you in."
else
  oops "It would not accept your own password ($code). Run this again."
  exit 1
fi

say "Done."
echo "Your relay: $url"
echo
echo "Nothing else to set up, and nothing to remember — the password is in your"
echo "Keychain under '$SERVICE' and the apps read it from there."
echo
echo "There is nothing on it yet: the buttons that put a film there are the next"
echo "piece of work, and are not built."
