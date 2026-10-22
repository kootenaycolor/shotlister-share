#!/bin/bash
# Prove the engine reads a film the same way in a browser as it does on the Mac.
#
#   ./web/proof.sh "~/…/Call Her Back.shotlist"
#
# Reads the film's change logs twice — once natively, once inside WebAssembly in
# a browser — and compares every field of every record. Nothing is written to
# the film: the logs are read where they lie and the pictures are linked, not
# copied.
set -e
FILM="${1:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Shotlister/Call Her Back.shotlist}"
PORT="${PORT:-8731}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"

[ -d "$FILM/changes" ] || { echo "no changes/ folder in $FILM"; exit 1; }

echo "Building the engine for a browser…"
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --quiet --manifest-path "$HERE/web/Cargo.toml" --target wasm32-unknown-unknown --release

mkdir -p "$OUT/logs"
cp "$FILM"/changes/*.log "$OUT/logs/"
[ -d "$FILM/media/proxies" ] && ln -s "$FILM/media/proxies" "$OUT/media"
cp "$HERE/web/target/wasm32-unknown-unknown/release/shotlister_web.wasm" "$OUT/"
cp "$HERE/web/proof/index.html" "$OUT/"
ls "$OUT/logs" | sort | python3 -c "import sys,json;print(json.dumps([l.strip() for l in sys.stdin]))" > "$OUT/logs.json"

echo "Reading it on the Mac…"
cargo run --quiet --manifest-path "$HERE/web/Cargo.toml" --example reference -- "$OUT/logs" \
  | python3 -c "
import sys, json
got = dict(line.split('\t', 1) for line in sys.stdin.read().splitlines())
json.dump({'summary': got['summary'],
           'fpBytes': int(got['fingerprint-bytes']),
           'fpSha': got['fingerprint-sha'],
           'viewBytes': int(got['view-bytes']),
           'viewSha': got['view-sha']}, open('$OUT/expected.json', 'w'))
print('  ', got['summary'])
"

echo
echo "Now open this and read the verdict at the top:"
echo "   http://127.0.0.1:$PORT/index.html"
echo "(ctrl-C to stop)"
cd "$OUT" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1
