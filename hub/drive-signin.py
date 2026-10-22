#!/usr/bin/env python3
"""The portal's own Google sign-in, read-only — run once.

A page that follows a Google Doc (`src/docfollow.js`, Halcyon's Outline) has
the portal ask Drive for the doc on its own clock, with the Mac asleep. For
that the worker holds a Google sign-in as the secret `GDRIVE`.

**Read only, on purpose.** Uplift's sign-in for the same account can do
anything to his Drive; this one asks for `drive.readonly` and nothing else, so
a leak from Cloudflare reads and never writes or deletes. It uses the same
Google app Uplift already uses (its client id and secret, read from
`~/.drive-accounts`), so there is nothing to set up in Google's console: his
browser opens, he picks owner@your-domain.example and presses Allow, and
the result goes straight into the worker with `wrangler secret put`. Nothing
is written to disk.

    python3 hub/drive-signin.py               sign in and put the secret
    python3 hub/drive-signin.py --print       sign in and print it instead

**`--write`** (2026-10-13, stage 3 step 6) makes the OTHER sign-in, the one
the server makes Drive folders with (`src/drivewrite.js`): the full `drive`
scope, put as the secret `GDRIVE_WRITE`, never `GDRIVE`. Google has no
narrower scope that can make a folder inside a folder the Mac made (the
`drive.file` scope only reaches what this app made itself or what he picks by
hand, one item at a time), so the limit is in the server's own code: it can
list, read, make a folder and make a small file — no move, rename, trash or
delete exists in it.

    python3 hub/drive-signin.py --write       the folder-making sign-in → GDRIVE_WRITE
"""

import http.server
import json
import os
import secrets
import ssl
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser

ACCOUNT = "owner@your-domain.example"
WRITE = "--write" in sys.argv
SCOPE = "https://www.googleapis.com/auth/drive" if WRITE else "https://www.googleapis.com/auth/drive.readonly"
SECRET = "GDRIVE_WRITE" if WRITE else "GDRIVE"
HUB = os.path.dirname(os.path.abspath(__file__))
UPLIFT = os.path.expanduser("~/.drive-accounts")

try:
    import certifi
    SSL = ssl.create_default_context(cafile=certifi.where())
except Exception:
    SSL = ssl.create_default_context()


def uplift_client():
    with open(os.path.join(UPLIFT, "index.json")) as f:
        acct = next(a for a in json.load(f) if a.get("email", "").lower() == ACCOUNT)
    with open(os.path.join(UPLIFT, ".token_cache.json")) as f:
        tok = json.loads(json.load(f)[acct["id"]]["token_json"])
    return tok["client_id"], tok["client_secret"]


def main():
    client_id, client_secret = uplift_client()
    state = secrets.token_urlsafe(16)
    got = {}

    class Answer(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("state", [""])[0] != state:
                self.send_response(400)
                self.end_headers()
                return
            got.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.send_header("content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("<p style='font:16px system-ui;margin:40px'>Done. You can close this tab.</p>".encode())
            threading.Thread(target=server.shutdown).start()

        def log_message(self, *a):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Answer)
    redirect = "http://127.0.0.1:%d/" % server.server_port
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": client_id, "redirect_uri": redirect, "response_type": "code",
        "scope": SCOPE, "access_type": "offline", "prompt": "consent",
        "login_hint": ACCOUNT, "state": state,
    })
    print("Opening Google in the browser — pick %s and press Allow." % ACCOUNT)
    webbrowser.open(url)
    server.serve_forever()
    if "code" not in got:
        sys.exit("Google said: %s" % got.get("error", "nothing"))

    body = urllib.parse.urlencode({
        "code": got["code"], "client_id": client_id, "client_secret": client_secret,
        "redirect_uri": redirect, "grant_type": "authorization_code"}).encode()
    with urllib.request.urlopen(urllib.request.Request(
            "https://oauth2.googleapis.com/token", data=body), timeout=30, context=SSL) as r:
        tok = json.loads(r.read())
    if "refresh_token" not in tok:
        sys.exit("Google gave no lasting sign-in back.")
    if SCOPE not in tok.get("scope", "").split():
        sys.exit("Google did not grant %s access to Drive." % ("folder-making" if WRITE else "read"))
    secret = json.dumps({"client_id": client_id, "client_secret": client_secret,
                         "refresh_token": tok["refresh_token"]})
    if "--print" in sys.argv:
        print(secret)
        return
    exe = os.path.join(HUB, "node_modules/.bin/wrangler")
    put = subprocess.run([exe, "secret", "put", SECRET], input=secret, text=True,
                         capture_output=True, cwd=HUB)
    if put.returncode != 0:
        sys.exit("The portal would not take it: " + (put.stderr or put.stdout)[-300:])
    print("The portal can make project folders on the Drive now (its switch is still off)." if WRITE
          else "The portal can read Google Docs now.")


if __name__ == "__main__":
    main()
