#!/usr/bin/env python3
"""
The talking half of `Move Spec Sheets.app` and `Spec Sheet Switch.app`
(2026-10-14). The AppleScript shows the dialogs; this knocks on the hub's
spec sheet doors and turns each answer into plain words for them.

    spec-sheets.py look        the look, as a summary; first line "MOVABLE <n> OF <m>"
    spec-sheets.py move        the move, with the confirming words; the result in words
    spec-sheets.py switch      "On" or "Off"
    spec-sheets.py switch on   the switch thrown (or "off"); answers "On"/"Off"

Exit 0 when the hub answered, 2 when there is no password on this Mac, 3 when
the hub could not be reached or refused. A failure's first line is PROBLEM and
the rest is something he can read; the AppleScript shows it as it is. (The
first line, not the exit code, is what the AppleScript reads: `do shell script`
turns a non-zero exit into an error that drops what was printed.)

**The password is read when he runs it, never kept.** It is the relay's sync
password, in his Keychain under the account `shotlister-relay-token`, the same
one `refresh.py` and the Mac app send. The hub's console door takes that same
value (`CONSOLE_TOKEN`, set to match by `hub/setup.sh`). It goes to curl in a
config file readable only by him and deleted straight after, never on a
command line where another program could see it.

For checks: `SHOTLISTER_HUB_CONSOLE` points this at a fake hub and
`SHOTLISTER_RELAY_TOKEN` hands in a made-up password, so a check never reads
the Keychain or reaches the real hub (`hub/specsheet-app.mjs`).
"""
import json
import os
import subprocess
import sys
import tempfile

HUB_CONSOLE = os.environ.get("SHOTLISTER_HUB_CONSOLE", "https://mcp.your-domain.example/console")
CONFIRM = "move the spec sheets"
BY = "Move Spec Sheets app"

NO_PASSWORD = (
    "The sync password is not on this Mac.\n\n"
    "Open Shotlister Studio on this Mac and set up Sync with your sync password, "
    "then run this again. Nothing was changed."
)


class Trouble(Exception):
    pass


def password():
    # Set at all, even empty, and the Keychain is never asked: a check of
    # "no password" must not go looking in his.
    if "SHOTLISTER_RELAY_TOKEN" in os.environ:
        return os.environ["SHOTLISTER_RELAY_TOKEN"].strip()
    got = subprocess.run(
        ["security", "find-generic-password", "-a", "shotlister-relay-token", "-w"],
        capture_output=True, text=True,
    )
    return got.stdout.strip() if got.returncode == 0 else ""


def ask(token, door, method="GET", body=None):
    """One knock on a console door: (status, answer as JSON or None, raw text)."""
    config = tempfile.NamedTemporaryFile("w", suffix=".curl", delete=False)
    os.chmod(config.name, 0o600)
    config.write(f'header = "Authorization: Bearer {token}"\n'
                 'header = "User-Agent: ShotlisterSpecSheets/1.0"\n'
                 "silent\nshow-error\n")
    if body is not None:
        config.write('header = "Content-Type: application/json"\n')
    config.close()
    args = ["curl", "--config", config.name, "--max-time", "120", "-X", method,
            "--write-out", "\n%{http_code}"]
    if body is not None:
        args += ["--data-binary", json.dumps(body)]
    try:
        got = subprocess.run(args + [f"{HUB_CONSOLE}/{door}"], capture_output=True, text=True)
    finally:
        os.unlink(config.name)
    if got.returncode != 0:
        raise Trouble("Could not reach the hub. Check the internet connection and try again. Nothing was changed.")
    text, _, code = got.stdout.rpartition("\n")
    status = int(code) if code.strip().isdigit() else 0
    try:
        answer = json.loads(text) if text.strip() else None
    except ValueError:
        answer = None
    return status, answer, text


def why_of(answer, text):
    if isinstance(answer, dict):
        for key in ("error", "why", "problem", "message"):
            if answer.get(key):
                return str(answer[key])
    return (text or "").strip()[:300] or "no reason given"


def refused(status, answer, text):
    if status == 401:
        return ("The hub did not accept the sync password on this Mac.\n\n"
                "Check the sync password in Shotlister Studio's Sync settings, then run this again. Nothing was changed.")
    return f"The hub said no ({status}): {why_of(answer, text)}"


def plural(n, one, many=None):
    return f"{n} {one if n == 1 else (many or one + 's')}"


def state_of(one):
    """What the move would do with this sheet, in words, and whether it writes."""
    if one.get("already"):
        return "already moved, left as it is", False
    if not one.get("sheet"):
        return "cannot be moved", False
    if not one.get("record"):
        return "no project record on the hub yet, skipped", False
    return "", True


def look(token):
    status, answer, text = ask(token, "studio/specsheet/look", "POST", {})
    if status != 200 or not isinstance(answer, dict):
        raise Trouble(refused(status, answer, text))
    report = answer.get("report") or []
    lines = []
    movable = 0
    for one in report:
        title = one.get("title") or "Untitled sheet"
        sheet = one.get("sheet") or {}
        cams = sheet.get("cameras") or []
        cam_words = ", ".join(
            f"{c.get('label', '')} {c.get('body') or 'no camera named'}".strip() for c in cams
        ) or "no cameras"
        lenses = len(sheet.get("lenses") or [])
        unplaced = sum(1 for f in (one.get("flags") or []) if f.get("level") == "unplaced")
        said, writes = state_of(one)
        movable += 1 if writes else 0
        line = f"{title} · {cam_words} · {plural(lenses, 'lens', 'lenses')}"
        if unplaced:
            line += f" · {plural(unplaced, 'line')} not placed"
        if said:
            line += f" · {said}"
        lines.append(line)
    print(f"MOVABLE {movable} OF {len(report)}")
    print("\n".join(lines) if lines else "No spec sheets found in Notion.")


def move(token):
    status, answer, text = ask(token, "studio/specsheet/move", "POST", {"confirm": CONFIRM, "by": BY})
    if status != 200 or not isinstance(answer, dict):
        raise Trouble(refused(status, answer, text) + "\n\nNothing was written to Notion.")
    done = answer.get("done") or []
    moved = [d for d in done if d.get("written")]
    failed = [d for d in done if not d.get("written") and d.get("why")]
    left = [d for d in done if not d.get("written") and not d.get("why")]
    out = ["DONE", f"{plural(len(moved), 'spec sheet')} moved."]
    if failed:
        out.append("")
        out.append(f"{plural(len(failed), 'sheet')} failed:")
        out += [f"{d.get('title') or 'Untitled sheet'} · {d['why']}" for d in failed]
    if left:
        out.append("")
        out.append(f"Left as they were: {', '.join(d.get('title') or 'Untitled sheet' for d in left)}")
    out.append("")
    out.append("Nothing was written to Notion.")
    print("\n".join(out))


def switch(token, want=None):
    if want is None:
        status, answer, text = ask(token, "studio/specsheet")
    else:
        status, answer, text = ask(token, "studio/specsheet", "PUT", {"on": want == "on", "by": "Spec Sheet Switch app"})
    if status != 200 or not isinstance(answer, dict):
        raise Trouble(refused(status, answer, text))
    print("On" if answer.get("on") is True else "Off")


def main(argv):
    what = argv[1] if len(argv) > 1 else ""
    if what not in ("look", "move", "switch") or (what == "switch" and len(argv) > 2 and argv[2] not in ("on", "off")):
        print("PROBLEM\nspec-sheets.py look | move | switch [on|off]")
        return 64
    token = password()
    if not token:
        print("PROBLEM\n" + NO_PASSWORD)
        return 2
    try:
        if what == "look":
            look(token)
        elif what == "move":
            move(token)
        else:
            switch(token, argv[2] if len(argv) > 2 else None)
    except Trouble as problem:
        print("PROBLEM\n" + str(problem))
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
