#!/bin/bash
# **Put a film's portal back** — from the copy the relay set aside before an
# Archive or Delete (`kept/<film>/<time>/`, since 2026-10-04), or from the
# never-delete mirror `portal.sh` keeps in iCloud Drive.
#
#     backup/restore-portal.sh <film id>                    # show what would come back, change nothing
#     backup/restore-portal.sh <film id> --apply            # put it back
#     backup/restore-portal.sh <film id> --from mirror      # from the iCloud mirror instead of kept/
#     backup/restore-portal.sh <film id> --stamp <time>     # a particular set-aside copy (newest otherwise)
#
# **It never overwrites.** A file is put back only if the portal has nothing at
# that name now — so a portal that has been used since keeps every newer
# change, and running this twice is harmless. It lists what it skipped and why.
#
# Reading goes through `portal-reader/` (list/get only). Writing, with
# --apply only, is `wrangler r2 object put --remote`, one file at a time.
# PORTAL_LOCAL=<folder> runs the whole thing against a throwaway bucket kept in
# that folder on this Mac (wrangler's local storage) — how it is tested; the
# account has no separate test bucket.

set -uo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

FILM="${1:-}"
[[ "$FILM" =~ ^[0-9a-f]{8,64}$ ]] || { echo "usage: restore-portal.sh <film id> [--apply] [--from kept|mirror] [--stamp <time>]"; exit 2; }
shift
APPLY=no; FROM=kept; STAMP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=yes ;;
    --from) FROM="${2:-}"; shift ;;
    --stamp) STAMP="${2:-}"; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
[[ "$FROM" = kept || "$FROM" = mirror ]] || { echo "--from is kept or mirror"; exit 2; }

BUCKET="${PORTAL_BUCKET:-shotlister}"
MIRROR="${SHOTLISTER_PORTAL_BACKUPS:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups}/mirror/bucket"
NODE_BIN="$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | tail -1)"
export PATH="$NODE_BIN:/opt/homebrew/bin:/usr/local/bin:$PATH"
WRANGLER="$HERE/../hub/node_modules/.bin/wrangler"
PORT=$(( 8800 + RANDOM % 200 ))
LOG="$(mktemp -t portal-restore)"
CONF="$(mktemp -d)/wrangler.toml"
sed "s/^bucket_name = .*/bucket_name = \"$BUCKET\"/; s|^main = .*|main = \"$HERE/portal-reader/read.js\"|" "$HERE/portal-reader/wrangler.toml" > "$CONF"
LOCAL="${PORTAL_LOCAL:-}"
if [ -n "$LOCAL" ]; then
  sed -i '' 's/^remote = true$/remote = false/' "$CONF"
  "$WRANGLER" dev --config "$CONF" --port "$PORT" --persist-to "$LOCAL" >"$LOG" 2>&1 &
else
  "$WRANGLER" dev --config "$CONF" --port "$PORT" >"$LOG" 2>&1 &
fi
READER=$!
trap 'kill $READER 2>/dev/null; pkill -P $READER 2>/dev/null; rm -f "$LOG"' EXIT
for _ in $(seq 1 90); do grep -q "Ready on" "$LOG" && break; sleep 1; done
grep -q "Ready on" "$LOG" || { echo "the reader did not start"; tail -5 "$LOG"; exit 1; }

FILM="$FILM" FROM="$FROM" STAMP="$STAMP" APPLY="$APPLY" BUCKET="$BUCKET" MIRROR="$MIRROR" \
PORT="$PORT" WRANGLER="$WRANGLER" LOCAL="$LOCAL" /usr/bin/python3 - <<'PY'
import json, os, subprocess, tempfile, urllib.parse, urllib.request

E = os.environ; BASE = f"http://localhost:{E['PORT']}"
film, src = E["FILM"], E["FROM"]
live_prefix = f"p/{film}/"
# What is the film's — never restored by this; the Mac and the daily backup hold it.
FILM_OWN = ("manifest.json", "logs/", "devices/", "media/")

def listing(prefix):
    out, cur = [], None
    while True:
        q = f"/list?prefix={urllib.parse.quote(prefix)}" + (f"&cursor={urllib.parse.quote(cur)}" if cur else "")
        page = json.load(urllib.request.urlopen(BASE + q, timeout=120))
        out += page["objects"]
        if not page["truncated"]: return out
        cur = page["cursor"]

def fetch(key):
    return urllib.request.urlopen(BASE + "/get?key=" + urllib.parse.quote(key, safe=""), timeout=180).read()

now = {o["key"][len(live_prefix):] for o in listing(live_prefix)}

if src == "kept":
    kept = listing(f"kept/{film}/")
    stamps = sorted({o["key"].split("/")[2] for o in kept})
    if not stamps:
        raise SystemExit(f"nothing set aside for {film} in kept/")
    stamp = E["STAMP"] or stamps[-1]
    if stamp not in stamps:
        raise SystemExit(f"no set-aside copy {stamp}; there are: {', '.join(stamps)}")
    base = f"kept/{film}/{stamp}/"
    files = {o["key"][len(base):]: ("kept", o["key"]) for o in kept if o["key"].startswith(base) and not o["key"].endswith("kept.json")}
    print(f"from the copy set aside at {stamp} ({len(files)} files)")
else:
    root = os.path.join(E["MIRROR"], "p", film)
    files = {}
    for dirpath, _, names in os.walk(root):
        for n in names:
            if n.endswith(".part"): continue
            rel = os.path.relpath(os.path.join(dirpath, n), root)
            files[rel] = ("mirror", os.path.join(dirpath, n))
    print(f"from the iCloud mirror ({len(files)} files under p/{film}/)")

back, skipped = [], []
for rel, where in sorted(files.items()):
    if rel.startswith(FILM_OWN) or rel == "manifest.json":
        skipped.append((rel, "the film's own — not a portal file")); continue
    if rel in now:
        skipped.append((rel, "the portal has it now — kept as it is")); continue
    back.append((rel, where))

for rel, why in skipped: print(f"  skip  {rel}  ({why})")
for rel, _ in back: print(f"  {'put back' if E['APPLY']=='yes' else 'would put back'}  {rel}")
if E["APPLY"] != "yes":
    print(f"\n{len(back)} would come back, {len(skipped)} left alone. Nothing changed — add --apply to do it.")
    raise SystemExit(0)

done = 0
for rel, (kind, ref) in back:
    data = fetch(ref) if kind == "kept" else open(ref, "rb").read()
    with tempfile.NamedTemporaryFile(delete=False) as t:
        t.write(data); path = t.name
    ctype = "application/json" if rel.endswith(".json") else ""
    where = ["--local", "--persist-to", E["LOCAL"]] if E.get("LOCAL") else ["--remote"]
    cmd = [E["WRANGLER"], "r2", "object", "put", f"{E['BUCKET']}/{live_prefix}{rel}", "--file", path] + where
    if ctype: cmd += ["--content-type", ctype]
    r = subprocess.run(cmd, capture_output=True, text=True)
    os.unlink(path)
    if r.returncode != 0:
        print(f"  FAILED {rel}: {(r.stderr or r.stdout).strip().splitlines()[-1:]}"); continue
    done += 1
print(f"\n{done} of {len(back)} put back, {len(skipped)} left alone.")
PY
