"""Every share link already sent, opened as a stranger would — before and after
a hub deploy (his rule, 2026-10-05: a link he has sent never breaks).

The links come from the portal's backup mirror in iCloud (shorts.json, each
film's people.json links that are not off, and views.json views that are not
off; a short name only when its film's general link is on). Each is fetched
with no cookie and no sign-in; what is kept is the answer
(status, where it landed without its query, the page's <title>), never a key.

    python3 hub/links-check.py before.json            # take the before
    python3 hub/links-check.py after.json before.json # take the after, compare

Exit 1 when any link answers differently after than before.
"""
import hashlib, json, pathlib, re, sys

MIRROR = pathlib.Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups/mirror/bucket"
HOST = "https://share.your-domain.example"


def general_link(film):
    """films.generalKeyOf: the film's first link with a key — and on."""
    try:
        people = json.loads((MIRROR / "p" / str(film) / "people.json").read_text())
    except (OSError, ValueError):
        return False
    first = next((l for l in people.get("links") or [] if isinstance(l, dict) and l.get("key")), None)
    return bool(first and not first.get("off"))


def links():
    out = []
    shorts = json.loads((MIRROR / "shorts.json").read_text())
    short_of = {v.get("project"): k for k, v in shorts.items() if isinstance(v, dict)}
    for short in sorted(shorts):
        # A short name stands for its film's general link (worker.js), so one
        # whose film has none, or has it off, was never a link anybody could
        # open: it answers "This film isn't shared", and is not counted.
        if not general_link(shorts[short].get("project") if isinstance(shorts[short], dict) else ""):
            continue
        out.append((f"short {short}", f"{HOST}/{short}"))
    for film in sorted(p.name for p in (MIRROR / "p").iterdir() if p.is_dir()):
        try:
            people = json.loads((MIRROR / "p" / film / "people.json").read_text())
        except (OSError, ValueError):
            people = {}
        for n, link in enumerate(people.get("links") or []):
            if link.get("key") and not link.get("off"):
                out.append((f"link {film[:8]} #{n} ({link.get('role', '')})", f"{HOST}/f/{film}?k={link['key']}"))
        try:
            views = json.loads((MIRROR / "p" / film / "views.json").read_text())
        except (OSError, ValueError):
            views = {}
        for view in views.get("views") or []:
            if view.get("code") and not view.get("off"):
                base = f"/{short_of[film]}" if film in short_of else f"/f/{film}"
                out.append((f"view {film[:8]} {view.get('name', '')}", f"{HOST}{base}/v/{view['code']}"))
    return out


def look(url):
    """curl, not urllib: this Mac's Python has no certificates to check with."""
    import subprocess, tempfile
    with tempfile.NamedTemporaryFile() as body:
        got = subprocess.run(["curl", "-sL", "--max-time", "30", "-A", "Mozilla/5.0 (links-check)", "-o", body.name,
                              "-w", "%{http_code} %{url_effective}", url], capture_output=True, text=True)
        if got.returncode != 0:
            return {"status": 0, "trouble": f"curl {got.returncode}"}
        text = pathlib.Path(body.name).read_bytes()[:200_000].decode("utf-8", "replace")
    status, _, landed = got.stdout.partition(" ")
    title = re.search(r"<title>(.*?)</title>", text, re.S)
    return {"status": int(status), "landed": landed.split("?")[0], "title": (title.group(1).strip() if title else "")[:120]}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    seen = {}
    for label, url in links():
        seen[hashlib.sha256(url.encode()).hexdigest()[:16]] = {"label": label, **look(url)}
    pathlib.Path(sys.argv[1]).write_text(json.dumps(seen, indent=1))
    works = sum(1 for v in seen.values() if v["status"] == 200)
    print(f"{len(seen)} links: {works} work, {len(seen) - works} do not")
    for v in seen.values():
        if v["status"] != 200:
            print(f"  {v['label']}: {v['status']}")
    if len(sys.argv) > 2:
        before = json.loads(pathlib.Path(sys.argv[2]).read_text())
        moved = [(k, before.get(k), seen.get(k)) for k in set(before) | set(seen)
                 if (before.get(k) or {}).get("status") != (seen.get(k) or {}).get("status")
                 or (before.get(k) or {}).get("title") != (seen.get(k) or {}).get("title")]
        for k, b, a in moved:
            print(f"  CHANGED {(a or b)['label']}: {b and b.get('status')} {b and b.get('title')!r} -> {a and a.get('status')} {a and a.get('title')!r}")
        print("no change" if not moved else f"{len(moved)} changed")
        return 1 if moved else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
