#!/bin/bash
# **A copy of the portal that nothing on the portal can take away.**
#
# Kept in iCloud Drive › "Shotlister Portal Backups".
#
# His ask, 2026-10-04: *"without wiping any data … I have teams relying on my
# current portal"*. Until now `backup.sh` kept the films' change logs and
# nothing else, so the portal's own files — who is invited, the share links,
# What Viewers See, the written pages, documents, boards, covers, the console's
# records — existed in exactly one place: the bucket. And the relay's whole-film
# remove (`removeProject`, behind Archive and Delete in Studio and on the phone,
# and DELETE FROM PORTAL in the console) deletes everything under the film's
# name, portal files included.
#
# ## What it keeps
#
# - **A mirror that never deletes.** Every object in the bucket (bar `mcp/`,
#   which is only the AI connector's sign-ins and is remade by signing in, and
#   `hub/logs/`, the hub's copy of each film's logs, which are already kept), kept
#   at its own path under `mirror/bucket/`. New and changed objects are
#   fetched; an object that disappears from the bucket **stays here** and is
#   named in `mirror/gone-from-server.txt`, so a wipe is visible and
#   undoable.
# - **A dated copy of the small files** — every `.json` (people, visible, front,
#   down, views, portal, covers, records, short names) plus the written pages —
#   zipped once a day under `daily/`, so a bad *edit* can be undone too,
#   not only a delete. A day costs well under a megabyte.
#
# ## How it reads, and why it cannot write
#
# `portal-reader/` is a two-route worker (list, get) run with `wrangler dev` on
# this Mac for the length of the backup, bound to the real bucket through his
# own wrangler login. It is never deployed and has no put or delete in it.
#
#     backup/portal.sh            # one run; prints one summary line

set -uo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

# **Its own folder, beside the films' and not inside it**: `restore.sh` lists
# every zip under "Shotlister Backups" as a film, so a portal day there would
# show up as a film called "daily".
INTO="${SHOTLISTER_PORTAL_BACKUPS:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups}"
NODE_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | tail -1)"
export PATH="$NODE_BIN:/opt/homebrew/bin:/usr/local/bin:$PATH"
WRANGLER="$HERE/../hub/node_modules/.bin/wrangler"
PORT=$(( 8800 + RANDOM % 200 ))
LOG="$(mktemp -t portal-reader)"

mkdir -p "$INTO/mirror/bucket" "$INTO/daily" || { echo "portal: could not make $INTO"; exit 1; }

"$WRANGLER" dev --config "$HERE/portal-reader/wrangler.toml" --port "$PORT" >"$LOG" 2>&1 &
READER=$!
trap 'kill $READER 2>/dev/null; pkill -P $READER 2>/dev/null; rm -f "$LOG"' EXIT

for _ in $(seq 1 90); do
  grep -q "Ready on" "$LOG" && break
  sleep 1
done
if ! grep -q "Ready on" "$LOG"; then
  echo "portal: the reader did not start (is wrangler signed in?)"
  tail -5 "$LOG"
  exit 1
fi

INTO="$INTO" PORT="$PORT" /usr/bin/python3 - <<'PY'
import hashlib, json, os, time, urllib.error, urllib.parse, urllib.request, zipfile, concurrent.futures as cf

INTO = os.environ["INTO"]; BASE = f"http://localhost:{os.environ['PORT']}"
MIRROR = os.path.join(INTO, "mirror"); BUCKET = os.path.join(MIRROR, "bucket")
TAGS = os.path.join(MIRROR, "etags.json")

def listing():
    out, cursor = [], None
    while True:
        q = "/list" + (f"?cursor={urllib.parse.quote(cursor)}" if cursor else "")
        page = json.load(urllib.request.urlopen(BASE + q, timeout=120))
        out += page["objects"]
        if not page["truncated"]: return out
        cursor = page["cursor"]

objects = [o for o in listing() if not o["key"].startswith(("mcp/", "hub/logs/"))]
known = json.load(open(TAGS)) if os.path.exists(TAGS) else {}

VANISHED = "vanished"

def fetch(o):
    path = os.path.join(BUCKET, o["key"])
    for _ in range(3):
        try:
            reply = urllib.request.urlopen(BASE + "/get?key=" + urllib.parse.quote(o["key"], safe=""), timeout=180)
            data = reply.read()
            # The file's own fingerprint as it was sent — a front.json rewritten
            # by refresh.py between the listing and the fetch is new, not broken.
            tag = reply.headers.get("x-etag") or o["etag"]
            whole = "-" in tag or hashlib.md5(data).hexdigest() == tag
            if whole:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                tmp = path + ".part"
                open(tmp, "wb").write(data); os.replace(tmp, path)
                return o["key"], tag
        except urllib.error.HTTPError as e:
            # Gone between the listing and the fetch (a short-lived lease file,
            # s/*-run.json): nothing to copy, not a failure.
            if e.code == 404:
                return o["key"], VANISHED
            time.sleep(2)
        except Exception:
            time.sleep(2)
    return o["key"], None

todo = [o for o in objects if known.get(o["key"]) != o["etag"] or not os.path.exists(os.path.join(BUCKET, o["key"]))]
failed, vanished = [], []
with cf.ThreadPoolExecutor(8) as pool:
    for key, tag in pool.map(fetch, todo):
        if tag == VANISHED: vanished.append(key)
        elif tag: known[key] = tag
        else: failed.append(key)
json.dump(known, open(TAGS, "w"))

# Kept, never deleted: name what the server no longer has.
here = {o["key"] for o in objects}
gone = sorted(k for k in known if k not in here)
with open(os.path.join(MIRROR, "gone-from-server.txt"), "w") as f:
    f.write("Files the portal no longer has. Every one of them is still in bucket/ beside this note.\n\n")
    f.write("\n".join(gone) + ("\n" if gone else ""))

# The day's small files, zipped.
small = [o["key"] for o in objects if o["key"].endswith(".json") or "/pages/" in o["key"] or "/decks/" in o["key"]]
day = time.strftime("%Y-%m-%d")
zpath = os.path.join(INTO, "daily", f"{day}.zip")
with zipfile.ZipFile(zpath + ".part", "w", zipfile.ZIP_DEFLATED) as z:
    for k in small:
        p = os.path.join(BUCKET, k)
        if os.path.exists(p): z.write(p, k)
os.replace(zpath + ".part", zpath)

print(f"portal: {len(objects) - len(vanished)} files, {len(todo) - len(failed) - len(vanished)} new or changed, "
      f"{len(failed)} failed, {len(gone)} gone from the server (kept), daily copy {day}.zip")
if failed:
    print("portal: did not copy — " + ", ".join(failed[:10]))
    raise SystemExit(1)
PY
