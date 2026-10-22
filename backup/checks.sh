#!/bin/bash
# The backup doors, checked — the two the Projects Console calls by name
# (`backup/backup.sh "Film"`, `backup/restore.sh "Film"`), 2026-09-15.
#
# Everything runs in folders of its own: a copy of the committed fixture for
# the films, a scratch folder for the backups, another for the Desktop. His
# real films and his real backups are never read or written here.
#
# Usage: backup/checks.sh            (from the repo root)
set -u
cd "$(dirname "$0")/.."

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ✓  %s\n' "$1"; }
no()  { fail=$((fail+1)); printf '  ✗  %s  (%s)\n' "$1" "$2"; }

BOX="$(mktemp -d)"
trap 'rm -rf "$BOX"' EXIT
mkdir -p "$BOX/films" "$BOX/into" "$BOX/desk"
cp -R studio/fixtures/Daybreak.shotlist "$BOX/films/Daybreak.shotlist"
export SHOTLISTER_FILMS="$BOX/films" SHOTLISTER_BACKUPS="$BOX/into" SHOTLISTER_DESKTOP="$BOX/desk"

# ---- backing up one film by name --------------------------------------------
got=$(./backup/backup.sh "daybreak" 2>&1); status=$?
line=$(echo "$got" | grep '^backed up: "Daybreak"  at "')
zip=$(echo "$line" | sed 's/^backed up: "Daybreak"  at "\(.*\)"$/\1/')
[ "$status" -eq 0 ] && [ -n "$zip" ] && [ -f "$zip" ] \
  && ok "one film is backed up by name, case blind, and the zip is where it says" \
  || no "one film is backed up by name, case blind, and the zip is where it says" "status $status: $got"
[ "$(ls "$BOX/into" | grep -c shotlist)" = 0 ] && [ "$(ls -d "$BOX/into"/*/ | wc -l | tr -d ' ')" = 1 ] \
  && ok "…and only that film" || no "…and only that film" "$(ls "$BOX/into")"

got=$(./backup/backup.sh "Daybreak" 2>&1)
echo "$got" | grep -q "^unchanged: \"Daybreak\"  at \"$zip\"" \
  && ok "…and an unchanged film names the backup that already stands for it" \
  || no "…and an unchanged film names the backup that already stands for it" "$got"

got=$(./backup/backup.sh "Nope" 2>&1); status=$?
[ "$status" -eq 1 ] && echo "$got" | grep -q '^refused: no film called "Nope"' \
  && ok "a film nobody has is refused, with status 1" || no "a film nobody has is refused, with status 1" "status $status: $got"

# ---- listing and restoring by name ------------------------------------------
stamp=$(basename "$zip" .zip)
got=$(./backup/restore.sh --list "Daybreak" 2>&1)
[ "$got" = "backup: \"Daybreak\"  $stamp  \"$zip\"" ] \
  && ok "the backups of a film are listed one per line" || no "the backups of a film are listed one per line" "$got"

got=$(./backup/restore.sh "daybreak" 2>&1); status=$?
to=$(echo "$got" | sed -n 's/^restored: "Daybreak"  from '"$stamp"'  to "\(.*\)"$/\1/p')
[ "$status" -eq 0 ] && [ -n "$to" ] && [ -d "$to/changes" ] && [ -f "$to/manifest.json" ] \
  && ok "the newest backup is restored by name, to the Desktop folder, whole" \
  || no "the newest backup is restored by name, to the Desktop folder, whole" "status $status: $got"
case "$to" in "$BOX/desk/"*) ok "…and never onto the live film";; *) no "…and never onto the live film" "$to";; esac
[ -d "$BOX/films/Daybreak.shotlist/changes" ] && ok "…which is still there, untouched" || no "…which is still there, untouched" "gone"
[ -d "$to/media" ] && ok "…with the pictures copied across from it" || no "…with the pictures copied across from it" "no media"

got=$(./backup/restore.sh "Daybreak" "$stamp" 2>&1)
echo "$got" | grep -q "^restored: \"Daybreak\"  from $stamp  to \"$BOX/desk/Daybreak (.*) 2.shotlist\"" \
  && ok "a particular stamp is restored, beside the first rather than over it" \
  || no "a particular stamp is restored, beside the first rather than over it" "$got"

got=$(./backup/restore.sh "Daybreak" "1999-01-01-0000" 2>&1); status=$?
[ "$status" -eq 1 ] && echo "$got" | grep -q '^refused: no backup of "Daybreak" stamped 1999-01-01-0000' \
  && ok "a stamp nobody has is refused" || no "a stamp nobody has is refused" "status $status: $got"
got=$(./backup/restore.sh "Nope" 2>&1); status=$?
[ "$status" -eq 1 ] && echo "$got" | grep -q '^refused: no backups of "Nope"' \
  && ok "…and so is a film with no backups" || no "…and so is a film with no backups" "status $status: $got"


# ---- the portal's copy: a file gone between listing and copying ------------
# (bug audit B2, 2026-10-19: s/drivecopies-run.json, a short-lived lease, made
# the first try "didn't finish" four days running.) The copy step of portal.sh
# is run against a stand-in reader that lists two files and has lost one.
got=$(BOX="$BOX" /usr/bin/python3 - <<'PY' 2>&1
import http.server, json, os, re, subprocess, threading
src = open("backup/portal.sh").read()
body = re.search(r"<<'PY'\n(.*?)\nPY\n", src, re.S).group(1)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith("/list"):
            out = json.dumps({"objects": [{"key": "p/a/front.json", "etag": "x-1"}, {"key": "s/drivecopies-run.json", "etag": "x-2"}], "truncated": False}).encode()
            self.send_response(200); self.end_headers(); self.wfile.write(out); return
        if "drivecopies-run" in self.path:
            self.send_response(404); self.end_headers(); self.wfile.write(b"missing"); return
        self.send_response(200); self.send_header("x-etag", "x-1"); self.end_headers(); self.wfile.write(b"{}")
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
into = os.path.join(os.environ["BOX"], "portal")
os.makedirs(os.path.join(into, "mirror", "bucket"), exist_ok=True); os.makedirs(os.path.join(into, "daily"), exist_ok=True)
r = subprocess.run(["/usr/bin/python3", "-c", body], env=dict(os.environ, INTO=into, PORT=str(srv.server_address[1])), capture_output=True, text=True)
print(r.returncode, r.stdout.strip().replace("\n", " | "))
PY
)
echo "$got" | grep -q '^0 portal: 1 files, 1 new or changed, 0 failed' \
  && ok "a portal file gone between listing and copying is not a failure" \
  || no "a portal file gone between listing and copying is not a failure" "$got"

echo "----"
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
