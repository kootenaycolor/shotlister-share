#!/usr/bin/env python3
"""Bring every film's words on the portal up to date, from Notion.

**Two sources, and neither of them is here.** The *film* knows what it is —
its title, its credits, its aspect ratio, how many scenes and shots and
locations and days it has. *Notion* knows what a person wrote about it — the
logline, the status, the shoot dates, which documents matter, the camera spec
sheet, who the crew are. This reads both and writes the small card the portal
draws from.

**Since 2026-09-16 the film half is the hub's, live.** The portal replays the
film's own change logs on every look (`hub/src/live.js`, `cardOf`) and lays
the credits, the ratio, the counts, the days and the pictures over whatever
this wrote — so a page is never behind the film, and nobody has to press
anything after a day's editing. This still reads the film, because the film
is what links a Notion page (its console page) and what the link covers are
drawn from; what it writes of the film is a fallback for a film not on the
relay yet. **Update the Portal is for the words.**

It is deliberately not clever. Every rule in it is one of his, written down:

- a document goes on the page **if and only if its `Hub` checkbox is ticked**;
- the camera spec sheet is copied verbatim, and anything blank stays off;
- the crew are the rows related to the project;
- the director is the row's Director relation, and the film's own only when
  the row names nobody;
- **the photograph he chose is never touched** — the portal is where that is
  set, and a refresh that silently changed it would be the worst kind of
  automation.

The Notion half needs a token and works without one: with no token it refreshes
what the film knows and leaves every word alone, which is still worth doing
after a day's editing.

    ./hub/refresh.py            every film
    ./hub/refresh.py "ZED"      one of them
"""

import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))

# **Where things sit in the bucket — `relay/layout.json`, named once.** The
# relay and the hub read the same file; this writes one thing into the bucket,
# the film's cover, and takes that key from there rather than spelling it.
with open(os.path.join(HERE, "..", "relay", "layout.json")) as _layout:
    LAYOUT = json.load(_layout)
ROOT = os.path.dirname(HERE)
# **`~/Documents/Shotlister`, a plain folder, since 2026-09-15.** The films
# left iCloud Drive that day (`design/DECISIONS.md`); this read the old place
# until 2026-09-16 and found only the stale copy of ZED there.
FILMS = os.path.expanduser("~/Documents/Shotlister")
BUCKET = "shotlister"
# The hub's console door — how this learns of a portal with no film behind
# it, which no folder on this Mac can say (2026-09-16). The token is the
# relay's, in the Keychain, the same one the Projects Console knocks with.
# A checking run points both at a local hub; neither is read anywhere else.
HUB_CONSOLE = os.environ.get("SHOTLISTER_HUB_CONSOLE", "https://mcp.your-domain.example/console")

# His own databases. Ids rather than names, because a database he renames is
# still the same database and a page that moves is still the same page.
PROJECTS = "feedface-0000-4000-8000-000000000001"
PROJECT_DOCS = "feedface-0000-4000-8000-000000000005"
CAMERA_SHEETS = "feedface-0000-4000-8000-000000000003"
CREW = "feedface-0000-4000-8000-000000000004"
# **A project that shoots more than once** (SL-1395, SL-1396, 2026-10-02):
# one row per shoot, each with its own dates, crew, spec sheet and documents.
# A project with no rows here is read exactly as it always was.
SHOOTS = "feedface-0000-4000-8000-000000000002"

# **2025-09-03, and it matters.** Notion's newer API moved a database's rows
# behind *data sources*: `POST /v1/data_sources/<id>/query`. On the old version
# that address does not exist, and the old `databases/<id>/query` does not
# accept a data source id — so the wrong pairing answers `invalid_request_url`
# for every database he has, which reads exactly like a token problem and is not
# one. Checked against his own workspace rather than assumed.
NOTION_VERSION = "2025-09-03"



def _stage(s):
    """Notion's "Complete" is the record's "Released" (2026-10-20, hub/src/stageword.js)."""
    return "Released" if str(s or "").strip().lower() in ("complete", "released") else s

def say(line):
    print(line, flush=True)


def stamp():
    """When this ran. So "did it update?" has an answer other than looking."""
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def moved(word, was, now):
    """`3 contacts` when it is the same, `1 → 3 contacts` when it is not."""
    many = f"{now} {word}{'' if now == 1 else 's'}"
    return many if was == now else f"{was} → {many}"


# ---------------------------------------------------------------- the films


def wrangler():
    local = os.path.join(HERE, "node_modules", ".bin", "wrangler")
    return [local] if os.path.exists(local) else ["npx", "--yes", "wrangler@4"]


class Stalled(Exception):
    """iCloud Drive did not answer in time."""


# **How long iCloud Drive may take to answer, and how long a whole run may
# take** (Ref 1409). 2026-10-02: a listing of the films folder sat inside
# macOS for thirteen minutes and never came back, and launchd starts no new
# run while one is still going — the portal would have stopped updating from
# the Mac until somebody noticed. A normal run is a few minutes.
ICLOUD_WAIT = 90
RUN_LIMIT = 25 * 60


def in_time(work, what, seconds=ICLOUD_WAIT):
    """`work()`, or `Stalled` if it has not answered in `seconds`.

    **A thread, so the wait can be walked away from.** A read iCloud is
    sitting on cannot be interrupted from Python; the thread is left behind,
    it holds nothing, and it goes when the run ends.
    """
    box = {}

    def run():
        try:
            box["got"] = work()
        except BaseException as problem:  # handed back to the caller below
            box["problem"] = problem

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(seconds)
    if worker.is_alive():
        raise Stalled(f"iCloud Drive did not answer in {seconds} s ({what})")
    if "problem" in box:
        raise box["problem"]
    return box.get("got")


def give_up_after(seconds):
    """**A ceiling on the whole run** — the last line, for anything `in_time`
    does not wrap. `os._exit` ends the process whatever it is waiting in, so
    the next scheduled run can start."""
    def stop():
        say(f"\nStopped: this run went past {seconds // 60} minutes. The next one starts on schedule.")
        os._exit(3)
    timer = threading.Timer(seconds, stop)
    timer.daemon = True
    timer.start()


def films_here(only=None):
    """Every film on this Mac that has been pushed to the relay — or none,
    said aloud, when iCloud Drive will not answer in time (Ref 1409)."""
    try:
        return in_time(lambda: _films_here(only), "listing the films")
    except Stalled as problem:
        say(f"{problem} — the films are left for the next run.")
        return []


def _films_here(only=None):
    """Every film on this Mac that has been pushed to the relay.

    **The relay's id, out of `remote.json`.** It is *not* the engine's own
    project id, which is the mistake that once put a second, empty film on his
    shelf: the hub lists a film for every `p/<id>/` prefix in the bucket, so an
    object written under the wrong id invents one.
    """
    found = []
    if not os.path.isdir(FILMS):
        say("Cannot find the Shotlister folder in Documents.")
        return found
    try:
        here = sorted(os.listdir(FILMS))
    except PermissionError:
        # **macOS, not the films.** Terminal has to be allowed into iCloud
        # Drive, and until it is, every path under it answers "operation not
        # permitted" — which as a Python traceback tells nobody anything.
        say("macOS will not let this read your iCloud Drive.")
        say("  Open System Settings → Privacy & Security → Files and Folders,")
        say("  find Terminal, and switch on iCloud Drive. Then run this again.")
        return found
    for name in here:
        if not name.endswith(".shotlist"):
            continue
        title = name[: -len(".shotlist")]
        if only and only.lower() not in title.lower():
            continue
        path = os.path.join(FILMS, name)
        try:
            with open(os.path.join(path, "remote.json"), encoding="utf-8") as f:
                remote = json.load(f)
        except (OSError, ValueError):
            say(f"  {title}: not on the relay yet — skipped")
            continue
        found.append({"title": title, "path": path, "project": remote.get("project", "")})
    return found


def relay_token():
    if os.environ.get("SHOTLISTER_RELAY_TOKEN"):
        return os.environ["SHOTLISTER_RELAY_TOKEN"]
    got = subprocess.run(
        ["security", "find-generic-password", "-a", "shotlister-relay-token", "-w"],
        capture_output=True, text=True,
    )
    return got.stdout.strip() if got.returncode == 0 else ""


def console(token, door, method="GET", body=None):
    """One knock on the hub's console door, over curl — for the reason
    `notion` gives: this Python has no certificate store. The token goes in
    a config file, never on the command line."""
    config = tempfile.NamedTemporaryFile("w", suffix=".curl", delete=False)
    os.chmod(config.name, 0o600)
    config.write(f'header = "Authorization: Bearer {token}"\n'
                 'header = "User-Agent: ShotlisterRefresh/1.0"\n'
                 "silent\nshow-error\nfail-with-body\n")
    if body is not None:
        config.write('header = "Content-Type: application/json"\n')
    config.close()
    args = ["curl", "--config", config.name, "--max-time", "30", "-X", method]
    if body is not None:
        args += ["--data-binary", json.dumps(body)]
    try:
        return subprocess.run(args + [f"{HUB_CONSOLE}/{door}"], capture_output=True, text=True)
    finally:
        os.unlink(config.name)


def carry_portals(films, portals):
    """A portal with no film behind it, carried into the film that names its
    page — asked for here, off the film's own project link.

    The hub does this on its own when the console's record names the film's
    relay id, and for Harbour Light Affair (2026-09-18) it never did: the
    console wrote the record three seconds after the film was made, before
    the film's first sync had given it an id, and did not write again. The
    film knows its project page (`console_page`, on the film itself) and this
    run knows every portal on its own, so it can put the two together without
    waiting on anybody's record. Answers the portals still standing.
    """
    if not films or not portals:
        return portals
    token = relay_token()
    if not token:
        return portals
    standing = {p["project"]: p for p in portals}
    for film in films:
        try:
            page = facts(film)["console_page"].replace("-", "")
        except (RuntimeError, ValueError, KeyError, AttributeError):
            continue
        if page not in standing:
            continue
        got = console(token, f"{page}/portal/carry", "POST", {"relay": film["project"]})
        try:
            answer = json.loads(got.stdout)
        except ValueError:
            answer = {}
        if got.returncode == 0 and answer.get("carried") is not None:
            moved = answer["carried"]
            said = ", ".join(f"{moved[k]} {k}" for k in ("people", "links", "sections", "documents", "objects") if moved.get(k))
            say(f"\n{film['title']}: carried its portal on its own into the film ({said or 'nothing left to move'})")
            del standing[page]
        else:
            say(f"\n{film['title']}: could not carry its portal in: "
                f"{answer.get('problem') or (got.stderr or got.stdout).strip()[:120] or 'no answer'}")
    return list(standing.values())


def portals_here(only=None):
    """Every portal with no film behind it — asked of the hub, because nothing
    on this Mac knows. Its id is the project's Notion page id, so the words
    come straight from that page; there is no film to read.

    Without the relay's token this says so once and carries on with the
    films: a portal on its own is a rarer thing than a film, and a refresh
    that stops for it would leave every film's words behind.
    """
    token = relay_token()
    if not token:
        say("No relay token here — any portal without a film is left alone.")
        return []
    got = console(token, "portals")
    try:
        answer = json.loads(got.stdout)
        listed = answer["portals"]
        if not isinstance(listed, list):
            raise ValueError("not a list")
    except (ValueError, KeyError, TypeError):
        problem = ""
        try:
            problem = str(json.loads(got.stdout).get("problem") or "")
        except (ValueError, AttributeError):
            pass
        say(f"The hub would not list its portals: {problem or (got.stderr or got.stdout).strip()[:120] or 'no answer'}")
        return []
    found = []
    for one in listed:
        title = str(one.get("title") or "")
        project = str(one.get("project") or "")
        if not re.fullmatch(r"[0-9a-f]{32}", project):
            continue
        if only and only.lower() not in title.lower():
            continue
        found.append({"title": title or project, "project": project})
    return found


IMAGES = ("jpg", "jpeg", "png", "webp", "heic")


def proxy_named(proxies, digest):
    """The stored name of a picture, or nothing.

    Every file is kept by its own contents, and the relay holds it under the
    first 32 characters of that hash plus the proxy's extension — the same name
    the photograph picker offers and the same one `/pic/` serves.

    **An image extension is preferred over the file's own**, which is what makes
    a clip work: a video's proxy is an `.mp4` beside a `.png` of its first
    frame, and the poster is the thing a page can draw.
    """
    if not digest:
        return ""
    stem = digest[:32]
    for extension in IMAGES:
        if os.path.exists(os.path.join(proxies, f"{stem}.{extension}")):
            return f"{stem}.{extension}"
    return ""


def some_pictures(groups, proxies, want):
    """One picture from each thing, then more from the front, up to `want`.

    Going round once first is what makes a mosaic show four *different* boards
    rather than four pictures off the same one.
    """
    picked = []
    for round_ in range(4):
        for media in groups:
            if len(picked) >= want:
                return picked
            if round_ < len(media):
                name = proxy_named(proxies, media[round_].get("hash", ""))
                if name and name not in picked:
                    picked.append(name)
    return picked


def drawn_with(view, proxies):
    """What each way in is drawn with: frames, location photographs, board pictures.

    **Names only.** The pictures are already in the bucket, put there by the
    Mac; this is the film saying which of them stand for what, so the portal can
    draw a page without replaying a hundred change logs to find out.
    """
    # A frame off the front of each scene, in the film's own order. The scenes
    # carry no pictures themselves — the shots do — so the rows are read once
    # and the first framed shot of each scene wins.
    first_frame = {}
    for group in view.get("groups", []):
        for row in group.get("rows", []):
            scene = row.get("sceneId", "")
            frame = row.get("frame") or {}
            if scene and scene not in first_frame and frame.get("hash"):
                first_frame[scene] = frame["hash"]

    scenes = []
    for scene in view.get("scenes", []):
        if scene.get("archived"):
            continue
        name = proxy_named(proxies, first_frame.get(scene.get("id", ""), ""))
        if name and name not in scenes:
            scenes.append(name)
        if len(scenes) >= 8:
            break

    return {
        "scenes": scenes,
        "locations": some_pictures([l.get("media", []) for l in view.get("locations", [])], proxies, 5),
        "boards": some_pictures([b.get("media", []) for b in view.get("boards", [])], proxies, 6),
    }


_FACTS = {}


def facts(film):
    """What the film itself says. The engine, asked rather than guessed at —
    once a run; the carry asks before the refresh does."""
    if film["path"] in _FACTS:
        return json.loads(_FACTS[film["path"]])
    found = _facts(film)
    _FACTS[film["path"]] = json.dumps(found)
    return found


def _facts(film):
    # **A time limit**, because the film is read off iCloud Drive (Ref 1409).
    # Generous: the first run after a change to the engine compiles it.
    try:
        got = subprocess.run(
            ["cargo", "run", "-q", "--manifest-path", os.path.join(ROOT, "ffi/Cargo.toml"),
             "--example", "dump_view", "--", film["path"], "view"],
            capture_output=True, text=True, cwd=ROOT, timeout=600,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("reading the film took over ten minutes — iCloud Drive may not be answering") from None
    if got.returncode != 0:
        raise RuntimeError(got.stderr.strip().splitlines()[-1] if got.stderr else "could not read the film")
    view = json.loads(got.stdout)
    project = view.get("project", {})
    pictures = 0
    proxies = os.path.join(film["path"], "media", "proxies")
    try:
        pictures = in_time(lambda: len([p for p in os.listdir(proxies) if p.lower().rsplit(".", 1)[-1]
                                        in ("jpg", "jpeg", "png", "heic", "webp")])
                           if os.path.isdir(proxies) else 0, "counting the film's pictures")
        drawn = in_time(lambda: drawn_with(view, proxies), "finding the film's pictures")
    except Stalled as problem:
        raise RuntimeError(str(problem)) from None
    return {
        "pictures": drawn,
        # The days as the film has them, so the schedule is drawn as dates
        # rather than as a number. A day nobody has dated is left out — the
        # tile draws a calendar, and a calendar needs a date.
        "days": [{"label": d.get("label", ""), "date": d.get("date", "")}
                 for d in view.get("days", []) if d.get("date")][:12],
        "director": project.get("director", ""),
        "producer": project.get("producer", ""),
        "ratio": project.get("ratio", 0) or 0,
        "console_page": project.get("consolePage", ""),
        "counts": {
            "scenes": len(view.get("scenes", [])),
            "shots": sum(len(g.get("rows", [])) for g in view.get("groups", [])),
            "locations": len(view.get("locations", [])),
            "boards": len(view.get("boards", [])),
            "days": len(view.get("days", [])),
            "pictures": pictures,
        },
    }


# --------------------------------------------------------------- the bucket


def front_key(project):
    """The card's key, from the one layout file."""
    return LAYOUT["prefix"] + project + "/" + LAYOUT["hub"]["front"]


def card_now(project):
    got = subprocess.run(
        wrangler() + ["r2", "object", "get", f"{BUCKET}/{front_key(project)}", "--pipe", "--remote"],
        capture_output=True, text=True, cwd=HERE,
    )
    try:
        return json.loads(got.stdout)
    except ValueError:
        return {}


def put_card(project, card):
    path = f"/tmp/refresh-{project}.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(card, f)
    got = subprocess.run(
        wrangler() + ["r2", "object", "put", f"{BUCKET}/{front_key(project)}",
                      "--file", path, "--content-type", "application/json; charset=utf-8", "--remote"],
        capture_output=True, text=True, cwd=HERE,
    )
    os.remove(path)
    if got.returncode != 0:
        raise RuntimeError((got.stderr or got.stdout).strip().splitlines()[-1])


# --------------------------------------------------------------- the words


def token():
    got = subprocess.run(
        ["security", "find-generic-password", "-s", "shotlister-notion",
         "-a", "shotlister-notion-token", "-w"],
        capture_output=True, text=True,
    )
    return got.stdout.strip() if got.returncode == 0 else ""


class Refused(Exception):
    """Notion answered, and said no."""


def notion(path, body=None, key=""):
    """Ask Notion, over curl.

    **Not `urllib`, and the reason is worth writing down.** The python.org build
    on this Mac ships without a certificate store, so every HTTPS call out of it
    fails `CERTIFICATE_VERIFY_FAILED` before it reaches Notion at all. `curl`
    uses the system's own trust and simply works. This project already shells out
    to wrangler and cargo; one more is cheaper than a dependency, and it cannot
    break on somebody else's Python.

    The token goes in a config file rather than on the command line, so it never
    appears in the process list.
    """
    config = tempfile.NamedTemporaryFile("w", suffix=".curl", delete=False)
    os.chmod(config.name, 0o600)
    config.write(
        f'header = "Authorization: Bearer {key}"\n'
        f'header = "Notion-Version: {NOTION_VERSION}"\n'
        'header = "Content-Type: application/json"\n'
        "silent\nshow-error\nfail-with-body\n"
    )
    config.close()
    try:
        argv = ["curl", "--config", config.name, "--max-time", "30",
                f"https://api.notion.com/v1/{path}"]
        if body is not None:
            argv += ["-X", "POST", "-d", json.dumps(body)]
        got = subprocess.run(argv, capture_output=True, text=True)
    finally:
        os.unlink(config.name)
    if not got.stdout:
        raise Refused(got.stderr.strip() or "Notion did not answer")
    try:
        answer = json.loads(got.stdout)
    except ValueError:
        raise Refused("Notion answered with something that is not JSON") from None
    if isinstance(answer, dict) and answer.get("object") == "error":
        raise Refused(f"{answer.get('code')}: {answer.get('message', '')[:120]}")
    return answer


def plain(rich):
    return "".join(bit.get("plain_text", "") for bit in (rich or [])).strip()


def prop(row, name):
    """One property, whatever kind it is, as the words a person would read."""
    field = (row.get("properties") or {}).get(name)
    if not field:
        return ""
    kind = field.get("type")
    if kind in ("title", "rich_text"):
        return plain(field.get(kind))
    if kind == "select":
        return (field.get("select") or {}).get("name", "")
    if kind == "multi_select":
        return ", ".join(o.get("name", "") for o in field.get("multi_select") or [])
    if kind == "number":
        n = field.get("number")
        return "" if n is None else (str(int(n)) if float(n).is_integer() else str(n))
    if kind in ("url", "email", "phone_number"):
        return field.get(kind) or ""
    if kind == "checkbox":
        return "yes" if field.get("checkbox") else ""
    if kind == "date":
        return (field.get("date") or {}).get("start") or ""
    return ""


def dates(row, name):
    field = (row.get("properties") or {}).get(name) or {}
    got = field.get("date") or {}
    return {"start": (got.get("start") or "")[:10], "end": (got.get("end") or "")[:10]}


def relates_to(row, name, page):
    ids = [r.get("id", "").replace("-", "") for r in
           ((row.get("properties") or {}).get(name) or {}).get("relation") or []]
    return page.replace("-", "") in ids


def rows_of(source, key):
    """Every row of a data source, following the cursor."""
    out, cursor = [], None
    while True:
        body = {"page_size": 100}
        if cursor:
            body["start_cursor"] = cursor
        try:
            answer = notion(f"data_sources/{source}/query", body, key)
        except Refused as problem:
            raise RuntimeError(f"{source}: {problem}") from problem
        out.extend(answer.get("results", []))
        if not answer.get("has_more"):
            return out
        cursor = answer.get("next_cursor")


HEADINGS = {"logline": "logline", "director's note": "note", "visual language": "look"}


def PLACEHOLDER(words):
    """A template's words he has not replaced — `placeholder` in src/notion.js.

    "*Insert here*", and the Projects template's "Add the director's creative
    note here: …", which Halcyon carried onto its page (2026-09-23).
    """
    return bool(re.fullmatch(r"\*?insert here\*?", words, re.I)
                or re.match(r"add the director['’]s creative note here\b", words, re.I))


def prose(page, key):
    """The logline, the director's note and the visual language, off the page.

    They are written as headings with paragraphs under them. All three moved
    to properties of the row on 2026-10-05 (see `typed_words`); the headings
    are still read here for a page that has not been moved yet.
    """
    said = {"logline": "", "note": "", "look": ""}
    try:
        blocks = notion(f"blocks/{page}/children?page_size=100", None, key).get("results", [])
    except Refused:
        return said
    under = None
    for block in blocks:
        kind = block.get("type", "")
        if kind.startswith("heading_"):
            under = HEADINGS.get(plain(block.get(kind, {}).get("rich_text")).lower().strip())
        elif kind == "paragraph" and under:
            words = plain(block["paragraph"].get("rich_text"))
            # "*Insert here*" is a placeholder he has not filled in. Putting
            # that on a page a director reads is worse than an empty section.
            if words and not PLACEHOLDER(words):
                said[under] = (said[under] + " " + words).strip()
        elif kind in ("divider", "column_list", "child_database"):
            under = None
    return said


# ------------------------------------------------- a Notion page, drawn here
#
# **How he says "this page is my visual language bible".** His question,
# 2026-09-03: *"how do i tell the web app, 'hey i want this to be my visual
# language bible?' In notion?"*
#
# Two boxes on the Project Docs row, and no code:
#
#   `Hub`      ticked  — put this on the film's page. This already existed.
#   `Section`  set     — and draw it *as a section of its own*, under this name.
#
# `Section` empty is the old behaviour exactly: the row stays a link under
# Documents. Set it to `Visual Bible` and the page is drawn here instead of
# sending a crew member out to Notion, where they meet a sign-in wall the
# portal knows nothing about. Set it to `Overheads` and a section called
# Overheads appears — which is the other half of his question, and the answer is
# that adding one is a Notion property, not a release.
#
# **Nothing is fetched that he has not ticked.** The rule the whole file is
# built on does not change; this only decides how a ticked thing is drawn.

SECTION_BLOCKS = {
    "heading_1": "h1", "heading_2": "h2", "heading_3": "h3",
    "paragraph": "p", "quote": "quote", "callout": "callout",
    "bulleted_list_item": "li", "numbered_list_item": "li", "to_do": "li",
    "toggle": "toggle", "image": "img", "divider": "hr",
    "column_list": "columns", "column": "column",
    # **His notes carry files and tables**, 2026-09-04 — two of his camera spec
    # sheets keep the LUT as an uploaded file in the body, and one keeps its
    # resolutions in a table. Both used to be dropped here without a word.
    "file": "file", "pdf": "file", "table": "table", "table_row": "trow",
    # **A clip** (Ref 1543): an uploaded one is kept like a file; a link stays
    # a link. An embed is a clip only when it is a player (`is_player`). The
    # same as `SECTION_BLOCKS` in `src/notion.js`.
    "video": "video", "embed": "video",
}

PLAYER_HOSTS = re.compile(
    r"^https?://(?:www\.)?(?:livid\.com/embed/|youtu\.be/|(?:m\.)?youtube(?:-nocookie)?\.com/(?:watch|embed/|shorts/)"
    r"|vimeo\.com/\d|player\.vimeo\.com/video/)", re.I)


def is_player(url):
    """Whether an address plays as a clip — `playerOf` in `src/paper.js`."""
    return bool(PLAYER_HOSTS.match(url or ""))


def slug_of(name):
    """A name a URL can carry, and the same one every run."""
    made = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")
    return made or "section"


# **A section he names the Visual Bible *is* the Visual Bible.**
#
# His instruction, 2026-09-05: take the bible out of Notion and put it on *"the
# visual language bible web app page"* — that page, not a second row beside it.
# Without this, `Section: Visual Bible` slugs to `visual-bible`, which collides
# with nothing, so the portal drew two rows called Visual Bible in two different
# parts of the rail: the built-in one holding the two paragraphs off the film's
# own Notion page, and his forty-picture bible filed under Details.
#
# So it lands on `bible` and is drawn under those paragraphs.
#
# **Only this one.** The other three built-in pages are a database each — the
# camera sheet, the crew, the pinned documents. A section folded onto one of
# those would be written to a key nothing ever reads and would go missing in
# silence, which is worse than a duplicate row.
BIBLE_NAMES = {"bible", "visual-bible", "visual-language-bible"}


def page_column(doc):
    """What this row is called on the film's sidebar, whichever way he named it.

    **His question, 2026-09-08:** *"I notice you added a column called Section to
    my Project Docs database, but section relates to a page or a section?"* It
    makes a **page**, and every word he reads says page — *Add → Written Page*,
    `set_page`, *Remove Page*. `Section` is the only place the old word survives,
    and the field behind it in `front.json` is still `sections`.

    So both names work. He can rename the column to `Page` whenever he likes, or
    never, and neither breaks: `Page` is asked for first because that is the word
    the rest of the product uses, and `Section` answers for as long as it exists.
    """
    return prop(doc, "Page") or prop(doc, "Section")


# **The film's own four screens, which no page he names may become.**
#
# `Locations` and `Schedule` are options in that Notion column today. Either
# would slug onto one of the film's own screens and put a *second* row of that
# name on the rail — one going into the program, one going to a page of words —
# with nothing to tell them apart. The portal's own Add screen has refused these
# names since it existed; Notion never has. So a row asking for one stays a
# document, and the run says so rather than quietly making the twin.
FILM_SCREENS = {"shotlist", "shots", "locations", "boards", "schedule"}


def section_slug(name):
    """Where a section he has named is drawn."""
    made = slug_of(name)
    return "bible" if made in BIBLE_NAMES else made


def linked(rich):
    """Rich text as words plus any links, and nothing else.

    Bold and italic are dropped on purpose. A visual bible is read on a phone on
    a set; what matters is the words, the pictures and being able to follow a
    link. Carrying six kinds of emphasis across would be carrying Notion's look
    into a page that has its own.
    """
    out = []
    for bit in rich or []:
        words = bit.get("plain_text", "")
        if not words:
            continue
        href = bit.get("href") or ""
        out.append({"s": words, "u": href} if href else {"s": words})
    return out


def bucket_args(into=None):
    """Where a write goes: his bucket, or a local one a check has made.

    **Only so the whole path can be tried without touching the real bucket.**
    `refresh.py` never passes `into`; a check does, and then every write lands in
    `wrangler`'s own local store instead of the one his crew reads.
    """
    return ["--local", "--persist-to", into] if into else ["--remote"]


def mirror_picture(url, project, key, into=None):
    """Copy a picture out of Notion and into the film's own media.

    **Notion's own picture links expire**, in about an hour, so a page that
    pointed at them would be a page full of broken boxes by the afternoon —
    which is the fault he has just spent a day on from the other direction. So
    each one is fetched once and put in the bucket beside the film's own
    photographs, under the hash of its address, and served by the media route
    that already exists and already checks the link's key.
    """
    if not url:
        return ""
    name = hashlib.sha256(url.split("?")[0].encode()).hexdigest()[:32]
    ext = re.search(r"\.(jpe?g|png|gif|webp|avif)(?:\?|$)", url, re.I)
    name += "." + (ext.group(1).lower() if ext else "jpg")
    at = f"/tmp/refresh-pic-{name}"
    got = subprocess.run(["curl", "-sSL", "--max-time", "45", "-o", at, url],
                         capture_output=True, text=True)
    if got.returncode != 0 or not os.path.exists(at) or os.path.getsize(at) == 0:
        return ""
    put = subprocess.run(
        wrangler() + ["r2", "object", "put", f"{bucket_of(into)}/p/{project}/media/{name}",
                      "--file", at] + bucket_args(into),
        capture_output=True, text=True, cwd=HERE)
    os.remove(at)
    return name if put.returncode == 0 else ""


HELD_AT_MOST = 25 * 1024 * 1024


def host_of(url):
    """Where a link goes, in the words on a card."""
    return urllib.parse.urlparse(url).netloc.replace("www.", "") or "link"


def named_by(url, fallback=""):
    """A file's own name, off the end of its address."""
    path = urllib.parse.urlparse(url).path
    return urllib.parse.unquote(path.rsplit("/", 1)[-1]) or fallback


def mirror_file(url, project, into=None):
    """Copy a file Notion holds into the film's own media, and say what it is.

    **Notion's links to its own files expire within the hour**, exactly as its
    picture links do, so a page pointing straight at one would be a broken
    download by the afternoon. A file he uploaded is therefore fetched once and
    put in the bucket beside the film's photographs.

    A file that is really a link to somewhere else never comes through here —
    his ruling, 2026-09-04: *"if they are google drive links leave them that
    way, but if i upload a real file in the notes that needs to carry over."*

    Big things are left behind rather than dragged across: he said small files,
    and a refresh that tried to carry a 4GB grade would hang the whole run.
    """
    if not url:
        return {}
    stem = named_by(url)
    tail = stem.rsplit(".", 1)[-1] if "." in stem else ""
    ext = tail.lower() if re.fullmatch(r"[A-Za-z0-9]{1,8}", tail or "") else "bin"
    name = hashlib.sha256(url.split("?")[0].encode()).hexdigest()[:32] + "." + ext
    at = f"/tmp/refresh-file-{name}"
    got = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "--max-filesize", str(HELD_AT_MOST),
         "-o", at, url], capture_output=True, text=True)
    held = os.path.getsize(at) if os.path.exists(at) else 0
    if got.returncode != 0 or not held:
        if os.path.exists(at):
            os.remove(at)
        return {}
    put = subprocess.run(
        wrangler() + ["r2", "object", "put", f"{bucket_of(into)}/p/{project}/media/{name}",
                      "--file", at] + bucket_args(into),
        capture_output=True, text=True, cwd=HERE)
    os.remove(at)
    return {"file": name, "bytes": held} if put.returncode == 0 else {}


def files_on(row, name):
    """A Files property, as things the portal can point at.

    A file he uploaded is held by Notion behind a link that expires; a file that
    is really a Drive link is not held by Notion at all. They are told apart
    here and handled differently after: `held` is carried across, the rest stays
    a link.
    """
    field = (row.get("properties") or {}).get(name) or {}
    out = []
    for one in field.get("files") or []:
        outside = one.get("type") == "external"
        where = ((one.get("external") if outside else one.get("file")) or {}).get("url", "")
        if not where:
            continue
        said = (one.get("name") or "").strip()
        # Notion names an attached link after the link itself, which makes a
        # useless label. The column it came from is the better name.
        if not said or said.startswith("http"):
            said = name if outside else named_by(where, name)
        out.append({"name": said, "url": where, "held": not outside})
    return out


def without(tree, names):
    """The same notes with the files it names taken out.

    **He attaches the LUT twice** — once in the Production LUT column and once
    in the body of the sheet, which is a sensible thing to do in Notion and
    reads as a mistake here: the same file drawn twice on one page. The column
    wins, because that is the one the page calls Files.
    """
    kept = []
    for node in tree:
        if node.get("t") == "file" and (node.get("name") or "").strip().lower() in names:
            continue
        if node.get("k"):
            node["k"] = without(node["k"], names)
        kept.append(node)
    return kept


def carried_over(raw, project, into=None):
    """His files, ready to draw: the uploads copied here, the links left alone."""
    out = []
    for one in raw:
        if not one.get("held"):
            out.append({"name": one["name"], "url": one["url"]})
            continue
        got = mirror_file(one["url"], project, into)
        if got:
            out.append({"name": one["name"], "file": got["file"], "bytes": got["bytes"]})
    return out


def children_of(block, key):
    out, cursor = [], None
    while True:
        path = f"blocks/{block}/children?page_size=100"
        if cursor:
            path += f"&start_cursor={cursor}"
        try:
            answer = notion(path, None, key)
        except Refused:
            return out
        out += answer.get("results", [])
        if not answer.get("has_more"):
            return out
        cursor = answer.get("next_cursor")


def bucket_of(into=None):
    return "shotlister-preview" if into else BUCKET


def read_blocks(block, key, project, seen, depth=0, into=None):
    """One Notion page as a small tree this program can draw.

    Depth is capped because a page can hold a page can hold a page, and a bible
    with a loop in it would fetch until the timer killed it.
    """
    if depth > 4:
        return []
    made = []
    for raw in children_of(block, key):
        kind = raw.get("type", "")
        as_ = SECTION_BLOCKS.get(kind)
        if not as_:
            continue
        body = raw.get(kind, {})
        node = {"t": as_}
        if as_ == "img":
            where = body.get("file", {}).get("url") or body.get("external", {}).get("url", "")
            got = seen.get(where)
            if got is None:
                got = mirror_picture(where, project, key, into)
                seen[where] = got
            if not got:
                continue
            node["src"] = got
            node["cap"] = plain(body.get("caption"))
        elif as_ == "file":
            # **A file in the notes.** Uploaded here, it is copied across and
            # opens for anybody with the link; a link to Drive stays a link and
            # goes wherever it goes.
            outside = body.get("type") == "external"
            where = ((body.get("external") if outside else body.get("file")) or {}).get("url", "")
            if not where:
                continue
            node["name"] = plain(body.get("caption")) or (
                host_of(where) if outside else named_by(where, "File"))
            if outside:
                node["url"] = where
            else:
                got = seen.get(where)
                if got is None:
                    got = mirror_file(where, project, into)
                    seen[where] = got
                if not got:
                    continue
                node["src"] = got["file"]
                node["bytes"] = got["bytes"]
        elif as_ == "video":
            outside = kind == "embed" or body.get("type") == "external"
            where = body.get("url", "") if kind == "embed" else (
                (body.get("external") if outside else body.get("file")) or {}).get("url", "")
            if not where:
                continue
            if outside:
                if kind == "embed" and not is_player(where):
                    continue
                if not re.match(r"^https?://", where, re.I):
                    continue
                node["url"] = where
            else:
                got = seen.get(where)
                if got is None:
                    got = mirror_file(where, project, into)
                    seen[where] = got
                if not got:
                    continue
                node["src"] = got["file"]
            cap = plain(body.get("caption"))
            if cap:
                node["cap"] = cap
        elif as_ == "table":
            node["head"] = bool(body.get("has_column_header"))
        elif as_ == "trow":
            node["c"] = [linked(cell) for cell in body.get("cells") or []]
        elif as_ != "hr":
            node["r"] = linked(body.get("rich_text"))
            if as_ == "li":
                node["n"] = kind == "numbered_list_item"
        if raw.get("has_children") and as_ not in ("img", "file", "trow", "video"):
            node["k"] = read_blocks(raw["id"], key, project, seen, depth + 1, into)
        # An empty paragraph is a blank line in Notion and nothing at all here.
        if as_ == "p" and not node.get("r") and not node.get("k"):
            continue
        made.append(node)
    return made


# The record's own four pages, by the names the portal draws them under.
# Mirrors RECORD_PAGES in `src/worker.js`; a section named in Notion may take
# the `bible` or `camera` slot, and then its own name wins below.
RECORD_PAGES = [("script", "Script"), ("bible", "Visual Bible"), ("camera", "Camera Spec Sheet"),
                ("people", "People"), ("documents", "Documents")]
# Mirrors PROGRAM_PAGES in `src/worker.js`: the program's tabs, so a link to
# Locations unfurls on a card that says Locations.
PROGRAM_PAGES = [("shotlist", "Shot List"), ("locations", "Locations"),
                 ("boards", "Reference Images"), ("schedule", "Schedule"),
                 ("diagrams", "Diagrams")]


MONTHS = ["January", "February", "March", "April", "May", "June",
          "July", "August", "September", "October", "November", "December"]


def shoot_dates_text(shoot):
    """`2 – 4 November`, or `2 November`, or nothing at all.

    **Mirrors `shootDates` in `src/front.js`** — the same rule, the other side
    of the Python/JS line this file already sits on. Change one, change both.
    """
    start = (shoot or {}).get("start") or ""
    if not start:
        return ""
    sy, sm, sd = (int(p) for p in start.split("-"))
    end = (shoot or {}).get("end") or ""
    if not end or end == start:
        return f"{sd} {MONTHS[sm - 1]}"
    ey, em, ed = (int(p) for p in end.split("-"))
    if sm == em and sy == ey:
        return f"{sd} – {ed} {MONTHS[em - 1]}"
    return f"{sd} {MONTHS[sm - 1]} – {ed} {MONTHS[em - 1]}"


def covers_wanted(title, card):
    """Every card a link into this film may unfurl into: the film's, then one
    per page of the record. Keyed by slug; the film's own is ``""``."""
    mark = card.get("mark") or {}
    base = {
        "title": title,
        "path": mark.get("path") or "",
        "colour": mark.get("colour") or "",
        # **What the card has to say, not just its name.** His report,
        # 2026-09-23: a card with only a title read as empty. Both are
        # already on `card` — nothing new to fetch, just something new to draw.
        "status": card.get("status") or "",
        "shoot": shoot_dates_text(card.get("shoot")),
    }
    wanted = {"": dict(base, logline=card.get("logline") or "")}
    names = dict(RECORD_PAGES + PROGRAM_PAGES)
    for section in card.get("sections") or []:
        slug, name = section.get("slug") or "", section.get("name") or ""
        if slug and name and re.fullmatch(r"[a-z0-9-]{1,64}", slug):
            names[slug] = name
    for slug, name in names.items():
        wanted[slug] = dict(base, page=name)
    # **The film's mark as a PNG**, for Safari's tab and the iPhone's home
    # screen — neither draws an SVG. Keyed by a name no page slug can take.
    wanted[ICON] = dict(base, icon=True)
    return wanted


# The icon's key in `covers.json`: a dot, which a slug may not carry.
ICON = "icon.png"


def covers_drawn(project):
    """What was drawn last time, so an unchanged card is not drawn again."""
    got = subprocess.run(
        wrangler() + ["r2", "object", "get", f"{BUCKET}/p/{project}/media/covers.json",
                      "--pipe", "--remote"],
        capture_output=True, text=True, cwd=HERE,
    )
    try:
        drawn = json.loads(got.stdout)
        return drawn if isinstance(drawn, dict) else {}
    except ValueError:
        return {}


def put_cover(project, title, card, redraw=False):
    """
    The pictures a pasted link unfurls into — the film's, and one per page.

    **Drawn here because a Worker cannot draw.** There is no canvas in one, and
    the card has to be a raster — iMessage, Slack and Mail will not render an
    SVG `og:image`, which is the only place this is ever seen. So it is drawn
    by `cover.mjs` in the same browser engine that draws the portal, using the
    portal's own typeface, and left in the bucket beside the film's pictures.

    **It costs nothing new to keep up to date.** Everything on it — the mark,
    the colour, the title, the logline, the pages' names — is already on the
    card being written one line above, so a film that changes its icon in
    Notion, or gains a page, has new covers the next time this runs.

    **Only what changed is drawn.** His ask of 2026-09-10 gave every page its
    own card, which made this eight pictures instead of one; a fingerprint of
    each card's inputs is kept beside them in `covers.json`, and a run whose
    words have not moved launches no browser at all. `redraw` ignores that.
    """
    wanted = covers_wanted(title, card)
    prints = {slug: hashlib.sha256(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:16]
              for slug, spec in wanted.items()}
    drawn = {} if redraw else covers_drawn(project)
    todo = [slug for slug in wanted if drawn.get(slug) != prints[slug]]
    if not todo:
        return 0
    jobs = []
    for slug in todo:
        out = f"/tmp/refresh-cover-{project}-{'icon' if slug == ICON else slug or 'film'}.png"
        jobs.append(dict(wanted[slug], out=out))
    made = subprocess.run(["node", os.path.join(HERE, "cover.mjs"), json.dumps(jobs)],
                          capture_output=True, text=True, cwd=HERE)
    if made.returncode != 0:
        raise RuntimeError((made.stderr or made.stdout or "the cover would not draw").strip().splitlines()[-1])
    trouble = None
    for slug, job in zip(todo, jobs):
        if not os.path.exists(job["out"]):
            trouble = trouble or RuntimeError(f"the cover for “{slug or 'the film'}” would not draw")
            continue
        key = LAYOUT["prefix"] + project + "/" + (
            LAYOUT["icon"] if slug == ICON else
            LAYOUT["coverFor"].replace("{slug}", slug) if slug else LAYOUT["cover"])
        got = subprocess.run(
            wrangler() + ["r2", "object", "put", f"{BUCKET}/{key}",
                          "--file", job["out"], "--content-type", "image/png", "--remote"],
            capture_output=True, text=True, cwd=HERE,
        )
        os.remove(job["out"])
        if got.returncode != 0:
            trouble = trouble or RuntimeError((got.stderr or got.stdout).strip().splitlines()[-1])
            continue
        drawn[slug] = prints[slug]
    # A page taken off the rail keeps its old picture in the bucket, unlisted
    # and harmless; forgetting its fingerprint means it is drawn afresh if the
    # page ever comes back.
    drawn = {slug: print_ for slug, print_ in drawn.items() if slug in prints}
    at = f"/tmp/refresh-covers-{project}.json"
    with open(at, "w", encoding="utf-8") as f:
        json.dump(drawn, f)
    got = subprocess.run(
        wrangler() + ["r2", "object", "put", f"{BUCKET}/p/{project}/media/covers.json",
                      "--file", at, "--content-type", "application/json; charset=utf-8", "--remote"],
        capture_output=True, text=True, cwd=HERE,
    )
    os.remove(at)
    if trouble:
        raise trouble
    if got.returncode != 0:
        raise RuntimeError((got.stderr or got.stdout).strip().splitlines()[-1])
    return len(todo)


def put_page(project, slug, tree, into=None):
    at = f"/tmp/refresh-page-{project}-{slug}.json"
    with open(at, "w", encoding="utf-8") as f:
        json.dump(tree, f)
    got = subprocess.run(
        wrangler() + ["r2", "object", "put", f"{bucket_of(into)}/p/{project}/pages/{slug}.json",
                      "--file", at, "--content-type", "application/json; charset=utf-8"] + bucket_args(into),
        capture_output=True, text=True, cwd=HERE)
    os.remove(at)
    if got.returncode != 0:
        raise RuntimeError((got.stderr or got.stdout).strip().splitlines()[-1])


def sheet_prop(row, name):
    """A spec sheet field: pills (multi-select since 2026-10-13) one per
    line, the way every reader takes a line as an entry (src/entries.js)."""
    field = (row.get("properties") or {}).get(name) or {}
    if field.get("type") == "multi_select":
        return "\n".join(o.get("name", "") for o in field.get("multi_select") or [] if o.get("name"))
    return prop(row, name)


CAMERA_FROM = {
    "body": "Camera", "lenses": "Lenses", "format": "Shooting Format",
    "capture": "Capture Resolution",
    "colour": "Color Space", "codec": "Codec", "fps": "Frame Rate",
    "desqueeze": "Desqueeze",
    # a label per Production LUT (src/entries.js); "" until the property exists
    "luts": "LUT Labels",
}


SOURCES = ("notion", "notion-once", "here", "program")


def source_of(thing):
    """Where a page's or a document's words come from, when the card does not say.

    **`sourceFrom` and `document` in `hub/src/front.js` are the same rules**, and
    the two sides have to agree exactly: the portal *derives* a source for every
    film that already exists rather than migrating anything, so a card written
    before 2026-09-08 carries no `source` at all and both halves have to work out
    the same answer. Change one and change the other in the same breath.

    Two shapes go through here and they answer differently, which is why this is
    one function rather than two: a **page** says who wrote it in `by`, and a
    **document** says it by carrying a `file` — an upload is his, a bare link
    came from Notion. Anything that now states its `source` outright simply wins
    over both, which is how a link he pins from the portal is his.
    """
    said = thing.get("source")
    if said in SOURCES:
        return said
    by = thing.get("by")
    if by == "deck":
        return "program"
    if by == "mcp" or thing.get("file"):
        return "here"
    return "notion"


def both_kinds(already, from_notion_now):
    """Keep the documents that were uploaded here; refresh the ones that are links.

    **A refresh must never remove a file it did not put there.** Notion rows
    carry a `url` and nothing else, so replacing the list wholesale deleted
    every document uploaded straight to a film's page — a look book, mainly,
    which is the one thing a collaborator has to be able to open without an
    account anywhere. It went silently, and the next refresh did it again.

    So the two kinds are told apart by **where their words come from**, the same
    question `both_roads` asks one shelf along. A document whose source is not
    `notion` is his and is kept; one that is Notion's is replaced by whatever
    Notion says now. Where a name is on both lists his copy wins.

    **It used to ask whether the document carried a `file`**, which was the same
    answer for every card that existed — an upload is his, a link is Notion's —
    right up until he asked, 2026-09-08, to be able to pin *"a Google Drive
    folder or a YouTube video"* from the portal. A link made there carries a
    `url` and no `file`, so under the old test it was swept away by the next
    refresh, silently, and again the one after. `source_of` derives the old
    answer for every document written before this, so nothing is migrated.
    """
    mine = [d for d in already if source_of(d) != "notion"]
    named = {d.get("name", "").strip().lower() for d in mine}
    # A Notion document renamed on the portal keeps the portal's name: it
    # remembers Notion's in `was`, and the row Notion sends under that name
    # wears the portal's again instead of arriving as a second card.
    worn = {d["was"].strip().lower(): d.get("name", "") for d in already
            if d.get("was") and source_of(d) == "notion"}
    fresh = []
    for d in from_notion_now:
        key = d.get("name", "").strip().lower()
        fresh.append({**d, "name": worn[key], "was": d.get("name", "")} if key in worn else d)
    linked = [d for d in fresh
              if d.get("name", "").strip().lower() not in named]
    return mine + linked


def fed_by_notion(section):
    """Whether Notion still writes this page's words.

    **This replaced `by in ("mcp", "deck")`, and that is Ref 871.** The old test
    asked *who wrote it last*, so the moment an agent touched a page Notion was
    locked out of it for good — with no way back but unticking `Hub` in Notion
    and ticking it again, which nothing anywhere told him.

    His decision, 2026-09-08: *"Your recommendation is correct"* — **the source
    decides who wins, and it is changeable both ways.** So a page he hands back
    to Notion on the portal starts being fetched again on the next run, and a
    page he takes a snapshot of stops being fetched without anything being
    destroyed at either end.
    """
    return source_of(section) == "notion"


def both_roads(already, from_notion_now, named=None):
    """Keep the pages Notion is not feeding; refresh the ones it is.

    **The same fault `both_kinds` exists for, one shelf along.** A page of the
    record can now be written two ways: from a Hub-ticked Project Docs row, and
    from the MCP by an agent that has just worked something out. A refresh
    replaces `sections` with exactly what Notion says, so without this the
    second kind is swept off the rail within the hour of being made — the page
    itself still sitting in the bucket, unreachable, because nothing lists it.

    An agent's section carries `by: "mcp"`, a deck's carries `by: "deck"`, and
    both are kept whatever Notion says —
    **including where both name the same slug.** That last part is his decision
    of 2026-09-04, and it is the opposite of what this did on the day it was
    written: the film's page is now the *source* for a bible rather than a copy
    of one, so a refresh writing over what an agent put there would destroy the
    source once an hour. Notion keeps its own page; it simply stops being copied
    on top of this one.

    **To hand a page back to Notion:** set its Source to *Live from Notion* on
    the page itself — Ref 871, and the end of the one-way door. Unticking `Hub`
    in Notion and ticking it again still works, and so does `remove_page`.
    """
    # **A deck is the kind with most to lose.** His Call Her Back bible is a
    # design he tuned by hand and said plainly he does not want to lose; a
    # refresh sweeping its row off the rail would leave the published document
    # in the bucket with nothing pointing at it. Its source is `program`, so the
    # first branch below keeps it without naming decks at all.
    fresh = {s.get("slug"): s for s in from_notion_now}
    # **Whether Notion names a slug at all**, which is not the same question as
    # whether it was fetched this run: a page he has snapshotted is skipped by
    # the loop above and is still very much named. Passed in from Notion's own
    # list before the skipping; falling back to what was fetched keeps the old
    # two-argument calls working.
    says = set(named) if named is not None else set(fresh)
    kept = []
    for section in already:
        slug = section.get("slug")
        if not fed_by_notion(section):
            # His, or an agent's, or a deck's. Notion keeps its own page; it
            # simply stops being copied on top of this one.
            section["notion"] = slug in says
            kept.append(section)
            fresh.pop(slug, None)
            continue
        if slug in fresh:
            # **Notion's row, and Notion's to replace** — but the source is the
            # portal's own fact and does not come back from Notion, so it is
            # carried over rather than re-derived. Without this, handing a page
            # back to Notion would forget on the next run that it had been
            # handed back.
            took = dict(fresh.pop(slug))
            took["source"] = "notion"
            took["notion"] = True
            if section.get("by"):
                took["by"] = section["by"]
            kept.append(took)
            continue
        if section.get("by") in ("mcp", "deck"):
            # **Born on the portal and pointed at a Notion page that does not
            # name it.** Nothing feeds it, and nothing may delete it either:
            # *report, never invent — and never destroy.* Dropping it here would
            # leave the page itself in the bucket, unreachable.
            section["notion"] = slug in says
            kept.append(section)
        # Otherwise: Notion's row, and Notion has dropped it. Gone, as always.
    for one in fresh.values():
        one["notion"] = True
    return kept + list(fresh.values())


def mark_of(row):
    """The film's own icon and colour, out of its Notion row.

    **Drawn here rather than linked.** His projects carry Notion's built-in
    icons — a broken heart in red for Call Her Back — and the colour on the row
    beside them. Both become the film's identity on the portal, and the colour
    becomes the accent for its whole page.

    The icon is fetched once and its outline kept, rather than the address of
    it. A page a director opens must not go to notion.so for a picture: it
    would leak where he is, and it would be a hole in the page the day Notion
    is slow. Kept as an outline it also takes the film's colour by being told
    to, which an image never could.
    """
    icon = (row or {}).get("icon") or {}
    address = ""
    if icon.get("type") == "external":
        address = (icon.get("external") or {}).get("url", "")
    elif icon.get("type") == "file":
        address = (icon.get("file") or {}).get("url", "")
    elif icon.get("type") == "icon":
        # **A built-in icon arrives as a name and a colour, not an address.**
        # `{"type": "icon", "icon": {"name": "heartbroken", "color": "red"}}` is
        # what his own films carry, and reading only `external` quietly gave
        # every film no mark at all — no error, just a blank where the heart
        # should be. The address is the two parts joined.
        named = icon.get("icon") or {}
        who = str(named.get("name") or "")
        hue = str(named.get("color") or "gray")
        if re.fullmatch(r"[a-z0-9-]+", who) and re.fullmatch(r"[a-z_]+", hue):
            address = f"https://www.notion.so/icons/{who}_{hue}.svg"
    if "notion.so/icons/" not in address:
        return {}
    got = subprocess.run(["curl", "-fsS", "--max-time", "12", address],
                         capture_output=True, text=True)
    drawing = got.stdout or ""
    if not drawing:
        return {}
    outline = re.findall(r'<path[^>]*\sd="([^"]+)"', drawing)
    colour = re.findall(r'fill="(#[0-9A-Fa-f]{6})"', drawing)
    if not outline:
        return {}
    return {"path": outline[0], "colour": (colour[0] if colour else "").upper()}


def director_of(row, crew, fetch=None):
    """Who the row's `Director` relation points at, by name — or "" when it
    points at nobody.

    **Notion's, not the film's** — the console's ask, 2026-09-15: the Projects
    row's Director relation is where he keeps it, and a film linked to a row
    should say what the row says. Each relation is a Crew page; the crew were
    fetched already, so the name is read out of that list, and a page that is
    not in it is fetched through `fetch` when one is given. Two directors are
    joined the way a credit is: `Anna Lee & Ben Roe`.

    Empty when the row has no director, so the caller can leave the film's own
    value standing — Notion saying nothing is not Notion saying "nobody".
    """
    named = []
    known = {(mate.get("id") or "").replace("-", ""): mate for mate in crew}
    for who in ((row.get("properties") or {}).get("Director") or {}).get("relation") or []:
        page = (who.get("id") or "").replace("-", "")
        mate = known.get(page)
        if mate is None and fetch and page:
            try:
                mate = fetch(page)
            except Refused:
                mate = None
        name = prop(mate, "Name") if mate else ""
        if name:
            named.append(name)
    return " & ".join(named)


def bare(page):
    return (page or "").replace("-", "")


def related(row, name):
    """The page ids a relation holds, undashed."""
    return [bare(r.get("id")) for r in
            ((row.get("properties") or {}).get(name) or {}).get("relation") or []]


def shoot_name(title, project):
    """`Shoot 2` out of `Lets Bake — Shoot 2`: the row's title without the
    project's name in front of it, however the apostrophe was typed."""
    loose = lambda words: re.sub(r"[^a-z0-9]", "", (words or "").lower())
    parts = re.split(r"\s+[—–-]\s+", title or "", maxsplit=1)
    if len(parts) == 2 and loose(parts[0]) == loose(project):
        return parts[1].strip()
    return (title or "").strip()


_DEFAULT_SHOOT = re.compile(r"(?:principal|additional shoot(?:\s+\d+)?|shoot(?:\s+\d+)?)", re.I)


def shoot_parts(words):
    """**A shoot's own name** (2026-10-05) — `shootParts` in src/notion.js.
    `Shoot 2 · Malibu Pickup` → base `Shoot 2` (the slug and the `Shoot 2
    Details` match keep the number's), name `Malibu Pickup` (what the portal
    shows). Words with no name of their own are both, exactly as before."""
    said = (words or "").strip()
    m = re.search(r"\(?\bShoot\s+(\d+)\b\)?", said, re.I)
    if not m or _DEFAULT_SHOOT.fullmatch(said):
        return said, said
    own = " ".join(f"{said[:m.start()]} {said[m.end():]}".split()).strip(" \t·:—–|,-")
    if not own or _DEFAULT_SHOOT.fullmatch(own):
        return said, said
    return f"Shoot {m.group(1)}", own


def shoots_of(page, key, project=""):
    """The project's rows in Shoots, oldest first, or None when Notion would
    not say. An empty list is a project that shoots once, which is every
    project there was before 2026-10-02."""
    try:
        rows = rows_of(SHOOTS, key)
    except RuntimeError as problem:
        say(f"  could not read its shoots: {problem}")
        return None
    out = []
    for row in rows:
        if not relates_to(row, "Project", page):
            continue
        base, name = shoot_parts(shoot_name(prop(row, "Shoot"), project) or "Shoot")
        out.append({
            "id": bare(row.get("id")),
            "name": name,
            "base": base,
            "status": _stage(prop(row, "Status")),
            "dates": dates(row, "Dates"),
            "changes": prop(row, "What Changes"),
            "sections": [one.strip() for one in prop(row, "Shot List Section").split(",") if one.strip()],
            "crew": related(row, "Crew"),
            "sheets": related(row, "Camera Spec Sheet"),
            "docs": related(row, "Docs"),
            "created": row.get("created_time") or "",
        })
    out.sort(key=lambda one: (one["dates"]["start"] or "9999", one["created"]))
    return out


def lead_of(shoots):
    """The shoot the portal leads with: the earliest Upcoming one, or the
    latest of them all once every shoot has wrapped."""
    if not shoots:
        return None
    upcoming = [one for one in shoots if one["status"].lower() == "upcoming"]
    return upcoming[0] if upcoming else shoots[-1]


def sheet_for(shoot, sheets, page, shoots, label=""):
    """Which spec sheet a shoot uses, out of every row in Camera Spec Sheets.

    **The shoot's own first** — the sheet its row links to, or one whose
    `Shoot` names it. Then a sheet tagged to no shoot of this project (his
    rule: an empty Shoot means the whole project). Then the newest the
    project has, said aloud when there was a choice to make (SL-1395: it
    used to be whichever Notion happened to hand back first).
    """
    if shoot:
        own = [s for s in sheets
               if bare(s.get("id")) in shoot["sheets"] or shoot["id"] in related(s, "Shoot")]
        if own:
            return max(own, key=lambda s: s.get("created_time") or "")
    mine = [s for s in sheets if relates_to(s, "Projects", page)]
    if shoots:
        ours = {one["id"] for one in shoots}
        whole = [s for s in mine if not ours & set(related(s, "Shoot"))]
        mine = whole or mine
    if not mine:
        return None
    newest = max(mine, key=lambda s: s.get("created_time") or "")
    if len(mine) > 1:
        say(f"  {len(mine)} spec sheets{' for ' + label if label else ''} and none says which shoot — "
            f"using the newest, “{prop(newest, 'Title') or prop(newest, 'Lenses')}”")
    return newest


#: **The logline is a property of the Projects row** (2026-10-05, his pick —
#: option B of the Notion link proposal). It used to be the paragraph under a
#: "Logline" heading in the page; the words were copied into the property and
#: the heading taken out. A page that still has the heading and an empty
#: property is read the old way until it is moved. `typedWords` in
#: src/notion.js and `notionlink.notion_words` in Projects Console are the
#: same rule — change one, change all three.
#:
#: **The director's note and the visual language joined it** (2026-10-05, his
#: templates decision): two more properties of the row, "Director's Note" and
#: "Visual Language", read the same way — the box first, the old heading only
#: while the box is empty. Paragraph breaks in a box become single spaces, the
#: way the headings' paragraphs were always joined, so a moved note reads on
#: the portal exactly as it did.
TYPED = {"logline": "Logline", "note": "Director's Note", "look": "Visual Language"}


def one_line(words):
    """Paragraphs as the portal shows them: one line, single spaces."""
    return " ".join(str(words or "").split())


def typed_words(row, said):
    """Lay the row's Logline, Director's Note and Visual Language properties
    over what the page's headings said. An empty property leaves the
    heading's words; a filled one wins."""
    for field, column in TYPED.items():
        words = one_line(prop(row, column))
        if words:
            said[field] = words
    return said


def from_notion(page, key):
    """Everything his Notion says about one film."""
    row = notion(f"pages/{page}", None, key)
    said = typed_words(row, prose(page, key))
    said.update({
        "mark": mark_of(row),
        "status": _stage(prop(row, "Status")),
        "type": prop(row, "Type"),
        "length": prop(row, "Length"),
        "shoot": dates(row, "Shoot Dates"),
        "source": f"notion:{page}",
    })

    # **A project that shoots more than once** (SL-1395, SL-1396). None when
    # Notion would not say, which leaves the card's shoots as they were.
    shoots = shoots_of(page, key, prop(row, "Project"))
    known = shoots is not None
    shoots = shoots or []
    lead = lead_of(shoots)
    slug_for = {one["id"]: slug_of(one["base"]) for one in shoots}

    def tagged(doc):
        """The shoots a Project Docs row is tagged to — empty is all of them."""
        mine = set(related(doc, "Shoot"))
        return [slug_for[one["id"]] for one in shoots
                if one["id"] in mine or bare(doc.get("id")) in one["docs"]]

    # **Only what he has ticked.** His rule, and the whole of it.
    #
    # A ticked row with a `Section` is drawn here as its own section instead of
    # being listed as a link out; one without stays a document exactly as
    # before. See the note above `SECTION_BLOCKS`.
    documents, sections = [], []
    for doc in rows_of(PROJECT_DOCS, key):
        if not relates_to(doc, "Projects", page) or not prop(doc, "Hub"):
            continue
        name = prop(doc, "Name")
        section = page_column(doc)
        if section and section_slug(section) in FILM_SCREENS:
            say(f"  “{section}” is one of the film's own screens — “{name}” stays a document")
            section = ""
        if section:
            slug = section_slug(section)
            sections.append({
                "slug": slug,
                "name": section,
                "from": doc.get("id", "").replace("-", ""),
                "title": name,
                # **Said rather than worked out.** `front.js` can derive both
                # from `by` for every card that already exists, which is what
                # spares a migration — but a card that states them is a card
                # that can be read on its own, and `source` is about to become
                # the thing that decides who may write a page rather than a
                # label describing who did.
                "type": "sheet" if slug == "camera" else "page",
                "source": "notion",
                "shoots": tagged(doc),
            })
            continue
        documents.append({
            "name": name,
            "kind": "lookbook" if "look" in name.lower() else "document",
            "url": prop(doc, "URL") or doc.get("url", ""),
            "source": "notion",
            "shoots": tagged(doc),
        })
    said["documents"] = documents
    said["sections"] = sections

    # **The sheet is more than its ten boxes.** His point, 2026-09-04: he
    # uploads small files onto a spec sheet and writes notes on it, and none of
    # that used to leave Notion. The row's own page id and its Production LUT
    # travel out of here raw; the run copies the files and fetches the notes,
    # because only it knows which film they belong to.
    #
    # **Which sheet: the next shoot's** (SL-1395). A project with two sheets
    # used to get whichever Notion listed first.
    camera = {k: "" for k in CAMERA_FROM}
    sheet_page, sheet_files = "", []
    sheets = rows_of(CAMERA_SHEETS, key)
    sheet = sheet_for(lead, sheets, page, shoots)
    # **Each shoot on the card**, so the portal can say which is next even
    # when its own Notion connection cannot see Shoots. Left off when Notion
    # would not say, so a bad minute never wipes them.
    if known:
        said["shoots"] = []
        for one in shoots:
            own = sheet_for(one, sheets, page, shoots, one["name"])
            said["shoots"].append({
                "id": one["id"], "name": one["name"], "base": one["base"], "slug": slug_of(one["base"]),
                "status": one["status"], "start": one["dates"]["start"], "end": one["dates"]["end"],
                "changes": one["changes"], "sections": one["sections"],
                "sheet": bare(own.get("id")) if own else "",
                "sheet_edited": own.get("last_edited_time", "") if own else "",
                "camera": {field: sheet_prop(own, column) for field, column in CAMERA_FROM.items()} if own else {},
                # Carried and read in `words_from_notion`, which knows the film.
                "camera_files": files_on(own, "Production LUT") if own else [],
            })
    if sheet:
        camera = {field: sheet_prop(sheet, column) for field, column in CAMERA_FROM.items()}
        sheet_page = bare(sheet.get("id"))
        sheet_files = files_on(sheet, "Production LUT")
        if lead:
            say(f"  the spec sheet is {lead['name']}'s — {camera['lenses'] or 'no lenses named'}")
    said["camera"] = camera
    said["camera_sheet"] = sheet_page
    said["camera_files"] = sheet_files

    def person(mate):
        return {
            "name": prop(mate, "Name"), "role": prop(mate, "Role"),
            "department": prop(mate, "Department"), "company": prop(mate, "Company"),
            "email": prop(mate, "Email"), "phone": prop(mate, "Phone"),
        }

    everyone = rows_of(CREW, key)
    crew = [person(mate) for mate in everyone if relates_to(mate, "Projects", page)]
    # **Each shoot's own people** (SL-1396): the Crew rows whose Shoots names
    # it, and anybody on the project tagged to none of its shoots — his rule,
    # an empty Shoot means the whole project. The front leads with the next
    # shoot's, so a crew member reading People sees who is on *this* one.
    if shoots:
        ours = {one["id"] for one in shoots}
        on_some = {bare(r) for one in shoots for r in one["crew"]}
        whole = [mate for mate in everyone if relates_to(mate, "Projects", page)
                 and not ours & set(related(mate, "Shoots")) and bare(mate.get("id")) not in on_some]
        for one, kept in zip(shoots, said.get("shoots", [])):
            mine = [mate for mate in everyone
                    if one["id"] in related(mate, "Shoots") or bare(mate.get("id")) in one["crew"]]
            kept["crew"] = [person(mate) for mate in mine + whole]
        # **One shoot is no shoots** (his ruling): People is the project's.
        if lead and known and len(shoots) > 1:
            crew = next(kept["crew"] for one, kept in zip(shoots, said["shoots"]) if one is lead)
    said["crew"] = crew
    # **The director comes off the row, when the row names one.** Left out of
    # `said` otherwise, so `card.update(said)` keeps what the film says.
    director = director_of(row, everyone, lambda who: notion(f"pages/{who}", None, key))
    if director:
        said["director"] = director
    return said


#: Facts the project record may hold that the card shows, by the card's own
#: names (2026-10-05, the one-record plan, phase 5).
RECORD_OWNS = {"logline": "logline", "director": "director", "producer": "producer",
               "status": "status", "type": "type", "length": "length",
               "directors_note": "note", "visual_language": "look"}

#: Card fields that are prose: laid as one line, as the portal shows them
#: (`one_line`), so a record's paragraph breaks never look like a change.
PROSE = ("logline", "note", "look")


def record_facts(page):
    """The project record's typed facts for a Notion page id, or {}.

    Never raises and never waits long: a hub that does not answer, a record
    with no facts, or a hub that does not have the facts door yet all mean
    {} — and the card keeps what Notion said, exactly as before."""
    bare = (page or {}).get("id", "") if isinstance(page, dict) else str(page or "")
    bare = bare.replace("-", "")
    token = relay_token()
    if not bare or not token:
        return {}
    try:
        got = console(token, f"record/{bare}/facts")
        if got.returncode != 0:
            return {}
        return json.loads(got.stdout or "{}").get("facts") or {}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def record_view(page):
    """The record's facts and what the project hides — `({facts}, [hidden])`.

    One read of the whole record (`hidden` is the console's word on its
    readout, recordlayout.py). Never raises: a hub that does not answer is
    ({}, []) and the card keeps what Notion said."""
    bare = (page or {}).get("id", "") if isinstance(page, dict) else str(page or "")
    bare = bare.replace("-", "")
    token = relay_token()
    if not bare or not token:
        return {}, []
    try:
        got = console(token, f"record/{bare}")
        if got.returncode != 0:
            return {}, []
        record = json.loads(got.stdout or "{}")
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}, []
    hidden = record.get("hidden") if isinstance(record.get("hidden"), list) else []
    return record.get("facts") or {}, [str(h) for h in hidden]


#: A credit's line fact, where the console keeps one (credits.MIRRORS).
CREDIT_LINES = {"Executive Producer": "executive_producer", "Line Producer": "line_producer"}
_ROLE = re.compile(r"^[A-Za-z][A-Za-z /&'.-]{0,39}$")


def card_credits(facts, hidden=()):
    """The credits a card lists beyond the director and the producer —
    `cardCredits` in src/facts.js, the same rule."""
    one = (facts or {}).get("credits")
    listed = one.get("value") if isinstance(one, dict) else None
    off = set(hidden or ())
    out = []
    for c in listed if isinstance(listed, list) else []:
        if not isinstance(c, dict):
            continue
        role = str(c.get("role") or "")
        people = [" ".join(str(n).split())[:120] for n in c.get("people") or [] if str(n).strip()][:24]
        if (not _ROLE.match(role) or not people or role in ("Director", "Producer")
                or f"credit:{role}" in off or CREDIT_LINES.get(role, "") in off):
            continue
        out.append({"role": role, "people": people})
    return out[:16]


def from_record(card, facts, hidden=()):
    """Lay the record's typed facts over what Notion said. Returns the names
    that changed. A fact he typed wins; a field the record does not hold is
    left as Notion gave it; a field the project hides is left off the card.
    `layRecordFacts` in src/facts.js is the same rule."""
    moved = []
    for field, key in RECORD_OWNS.items():
        one = facts.get(field)
        if not isinstance(one, dict) or "value" not in one:
            continue
        value = one["value"]
        if isinstance(value, str) and key in PROSE:
            value = one_line(value)
        if isinstance(value, str) and card.get(key) != value:
            card[key] = value
            moved.append(key)
    for field, key in RECORD_OWNS.items():
        if field in (hidden or ()) and card.get(key):
            card[key] = ""
            moved.append(key)
    listed = card_credits(facts, hidden)
    if (card.get("credits") or []) != listed:
        card["credits"] = listed
        moved.append("credits")
    return moved


def page_for(film, fact, key, projects):
    """Which Notion project this film is, and **how it was found**.

    Its own link first, then its name. Returns `(page, how)` where `how` is
    `link`, `name` or `""`.

    **How it was found is not a detail.** His question, 2026-09-08: *"when
    you're making a new project, how do you even set that up in the first
    place, and what sets that up? ... It just sounds flimsy."* He is right, and
    this is the flimsy part: a film with no stored link is matched to its Notion
    row **by title, word for word**. Rename the row to "Call Her Back (2026)"
    and every word on the portal silently stops updating — no error, no empty
    page, just yesterday's card forever.

    Nothing has ever said which of the two a film is living on, so a film held
    together by a name match looked exactly like one held together properly.
    Saying so is the whole of the fix here; making the link the only road is a
    decision of his, not a change to slip in.
    """
    if fact["console_page"]:
        return fact["console_page"].replace("-", ""), "link"
    for row in projects:
        if prop(row, "Project").strip().lower() == film["title"].strip().lower():
            return row["id"].replace("-", ""), "name"
    return "", ""


# ------------------------------------------------------------------- the run


def covers_only(only):
    """
    Draw every film's link cover and nothing else.

    **A way to give the films that already exist a cover without a full run.**
    A refresh reads Notion and rewrites every word it finds; that is the right
    thing on a schedule and the wrong thing when all that is wanted is the
    picture. This touches one key per film and leaves the words alone.
    """
    films = films_here(only)
    if not films:
        say("No films here to draw.")
        return 1
    drawn, trouble = 0, 0
    for film in films:
        if not film["project"]:
            continue
        say(f"{film['title']}")
        try:
            n = put_cover(film["project"], film["title"], card_now(film["project"]), redraw=True)
            drawn += 1
            say(f"  its link covers are drawn — {n} of them")
        except (RuntimeError, OSError) as problem:
            trouble += 1
            say(f"  could not draw it: {problem}")
    say(f"Drew {drawn}." if not trouble else f"Drew {drawn}, and {trouble} would not.")
    return 1 if trouble else 0


def words_from_notion(card, page, how, key, project, was):
    """The Notion half of one card, films and portals alike: the row's words,
    the documents he ticked, each section's page, the spec sheet. Says what
    it did and returns how many things went wrong. Moved out of `main` on
    2026-09-16 so a portal with no film behind it walks the same road."""
    trouble = 0
    # **Said on the card, so the page can say it.** `link` is a film
    # that carries its Notion page's id; `name` is one held together by
    # its title matching, which breaks the day either is renamed and
    # says nothing when it does. Empty means this film has no Notion
    # page at all — which is not a fault on a film he has only just
    # made, and is why it is stated rather than warned about.
    card["linked"] = how
    if page:
        try:
            said = from_notion(page, key)
            said["documents"] = both_kinds(card.get("documents", []),
                                           said["documents"])
            # **Each section's page, fetched and put beside the film.**
            # Its pictures are copied into the film's own media on the
            # way past, because Notion's picture links expire within the
            # hour. Kept out of `front.json` on purpose: a bible is 40
            # pictures and 15,000 words, and every page of the portal
            # reads `front.json`. A section is only read when it is
            # opened.
            # **A page an agent has taken over is not fetched again.**
            # Keeping its row while overwriting its contents would be
            # the same destruction one level down.
            # **Asked of the source, not of who wrote last** — Ref 871.
            # `by in ("mcp", "deck")` was the old test and it is what
            # made an agent's touch permanent. See `fed_by_notion`.
            agents = {s.get("slug") for s in card.get("sections", [])
                      if not fed_by_notion(s)}
            kept = []
            for section in said.get("sections", []):
                if section.get("slug") in agents:
                    say(f"  “{section['name']}” is written on the portal now — left alone")
                    continue
                try:
                    tree = read_blocks(section["from"], key, project, {})
                except (RuntimeError, Refused) as problem:
                    say(f"  could not read “{section['name']}”: {problem}")
                    trouble += 1
                    continue
                if not tree:
                    continue
                put_page(project, section["slug"], tree)
                section["blocks"] = len(tree)
                kept.append(section)
                say(f"  “{section['name']}” drawn from Notion — {len(tree)} blocks")
            # **An agent's pages are not Notion's to delete.** See
            # `both_roads`: without this, a page written through the MCP
            # is swept off the rail by the next refresh and the file it
            # left behind becomes unreachable.
            said["sections"] = both_roads(
                card.get("sections", []), kept,
                {s.get("slug") for s in said.get("sections", [])})
            # **The spec sheet's files and notes.** The files follow his
            # ruling of 2026-09-04 — a Drive link stays a link, an
            # upload is carried across. The notes are a page like any
            # other and are kept beside the film under a name of their
            # own, so a section he happens to call Camera cannot land on
            # top of them.
            said["camera_files"] = carried_over(
                said.pop("camera_files", []), project)
            # Kept on the card too (Ref 1627): the spec sheet a film with no
            # Shoots rows edits from Shotlister, through the kit door.
            sheet = said.get("camera_sheet", "")
            notes = []
            if sheet:
                try:
                    notes = read_blocks(sheet, key, project, {})
                except (RuntimeError, Refused) as problem:
                    say(f"  could not read the spec sheet's notes: {problem}")
                    trouble += 1
            notes = without(notes, {one["name"].strip().lower()
                                    for one in said["camera_files"]})
            put_page(project, "camera-sheet", notes)
            said["camera_notes"] = len(notes)
            # **Every shoot's sheet, files and notes** (SL-1396), so an
            # earlier shoot's tab reads as it did. The lead's are the ones
            # just read; another shoot's are kept at `camera-sheet-<slug>`.
            had = {one.get("id"): one for one in card.get("shoots") or []}
            for one in said.get("shoots", []):
                raw = one.pop("camera_files", [])
                if one["sheet"] == sheet:
                    one["camera_files"], one["camera_notes"] = said["camera_files"], len(notes)
                    # Its own copy too, for when another shoot leads.
                    put_page(project, f"camera-sheet-{one['slug']}", notes)
                    continue
                # **Read again only when it changed** (Ref 1413). With many
                # shoots most are wrapped and their sheets never move; their
                # files and notes from the last run stand.
                # `last`, not `was`: `was` is this card's counts from the
                # caller, and reusing the name crashed every run on the first
                # film with two shoots from 10-02 to 10-04 (Ref 1502).
                last = had.get(one["id"]) or {}
                if (one["sheet"] and last.get("sheet") == one["sheet"] and last.get("sheet_edited") == one["sheet_edited"]
                        and "camera_notes" in last):
                    one["camera_files"], one["camera_notes"] = last.get("camera_files", []), last["camera_notes"]
                    continue
                one["camera_files"] = carried_over(raw, project)
                theirs = []
                if one["sheet"]:
                    try:
                        theirs = read_blocks(one["sheet"], key, project, {})
                    except (RuntimeError, Refused) as problem:
                        say(f"  could not read {one['name']}'s spec sheet notes: {problem}")
                        trouble += 1
                theirs = without(theirs, {f["name"].strip().lower() for f in one["camera_files"]})
                put_page(project, f"camera-sheet-{one['slug']}", theirs)
                one["camera_notes"] = len(theirs)
            if len(said.get("shoots", [])) > 1:
                lead = next((one for one in said["shoots"] if one["status"].lower() == "upcoming"),
                            said["shoots"][-1])
                say(f"  {len(said['shoots'])} shoots — the portal leads with {lead['name']}")
            elif "shoots" not in said and len(card.get("shoots") or []) > 1:
                # **Notion would not say** — the shoots on the card stand:
                # the front keeps the next shoot's people, and each row its tags.
                lead = next((one for one in card["shoots"] if one.get("status") == "Upcoming"),
                            card["shoots"][-1])
                if lead.get("crew"):
                    said["crew"] = lead["crew"]
                tags = {one.get("name"): one.get("shoots", [])
                        for one in card.get("documents", []) + card.get("sections", [])}
                for one in said["documents"] + said["sections"]:
                    one["shoots"] = one.get("shoots") or tags.get(one.get("name"), [])
            if notes or said["camera_files"]:
                say(f"  the spec sheet carries {len(notes)} note blocks "
                    f"and {len(said['camera_files'])} file(s)")
            card.update(said)
            say(f"  Notion: {moved('document', was['documents'], len(card['documents']))}, "
                f"{moved('contact', was['crew'], len(card['crew']))}"
                f"{', a camera spec sheet' if any(card['camera'].values()) else ''}")
        except (RuntimeError, Refused) as problem:
            say(f"  could not read Notion for it: {problem}")
            trouble += 1
    else:
        say("  no Notion project matches this film — its words are left as they were")

    return trouble


def portal_owner():
    """Who refreshes the portal: "hub" once its switch is thrown
    (`/console/studio/owner/portal`, 2026-10-11), "" for anything else —
    no token, no answer, an older hub — which is "carry on, as always"."""
    token = relay_token()
    if not token:
        return ""
    got = console(token, "studio/owner/portal")
    try:
        return str(json.loads(got.stdout).get("owner") or "") if got.returncode == 0 else ""
    except (ValueError, AttributeError):
        return ""


def main():
    give_up_after(RUN_LIMIT)
    # **The portal refreshes itself once its switch says so** (Projects
    # Console without the Mac, stage 3 step 2: `hub/src/refreshhub.js` does
    # all of this on the portal's own clock). Two writers of the same cards
    # and covers would only race each other, so this stands down — and comes
    # back by itself the moment the switch says "mac" again.
    if portal_owner() == "hub":
        say("The portal refreshes itself now (its switch says hub) — nothing to do here.")
        return 0
    # **Covers on their own.** `refresh.py --covers` draws the link cards and
    # writes nothing else; a bare run still draws them alongside the words.
    if len(sys.argv) > 1 and sys.argv[1] == "--covers":
        return covers_only(sys.argv[2] if len(sys.argv) > 2 else None)
    only = sys.argv[1] if len(sys.argv) > 1 else None
    key = token()
    if key:
        # **Ask Notion who this is before doing anything with it.** A token that
        # is refused, or one belonging to a workspace with nothing shared, both
        # answer every later question with silence — and silence reads exactly
        # like "he has not written anything yet".
        try:
            me = notion("users/me", None, key)
            whose = me.get("name") or (me.get("bot") or {}).get("owner", {}).get("type") or "Notion"
            say(f"Reading Notion as well, as {whose}.")
        except Refused as problem:
            say(f"Notion would not answer: {problem}")
            say("  Refreshing what the films know instead, and leaving every word alone.")
            key = ""
    else:
        say("No Notion token here — refreshing what the films know, and leaving every word alone.")

    films = films_here(only)
    portals = portals_here(only) if key else []
    # **A film that has arrived takes its portal with it**, before either is
    # refreshed — or the words would be written twice and the portal's copy
    # thrown away a moment later.
    portals = carry_portals(films, portals)
    if not films and not portals:
        say("No films to update.")
        return 0

    projects = []
    if key:
        try:
            projects = rows_of(PROJECTS, key)
        except RuntimeError as problem:
            say(f"Could not read his projects: {problem}")
            key = ""

    trouble = 0
    for film in films:
        say(f"\n{film['title']}")
        try:
            fact = facts(film)
        except (RuntimeError, ValueError) as problem:
            say(f"  could not read the film: {problem}")
            trouble += 1
            continue

        card = card_now(film["project"])
        before = json.dumps(card, sort_keys=True)
        was = {"documents": len(card.get("documents", [])), "crew": len(card.get("crew", []))}
        card.setdefault("version", 1)
        # **His photograph is never touched.** It is set on the portal, and a
        # refresh that changed it would be the worst kind of automation.
        card.update({k: v for k, v in fact.items() if k != "console_page"})

        if key:
            page, how = page_for(film, fact, key, projects)
            trouble += words_from_notion(card, page, how, key, film["project"], was)
            # **What he typed into the project record wins** (phase 5): over
            # Notion's words, never instead of them when the record says nothing.
            if page:
                took = from_record(card, *record_view(page))
                if took:
                    say(f"  from the project record: {', '.join(took)}")

        # **Say plainly whether anything moved.** Without this the only honest
        # answer to "did it update?" was to go and look, and a run that found
        # nothing new is indistinguishable from a run that failed.
        if json.dumps(card, sort_keys=True) == before:
            say("  nothing had changed")
        card["updated"] = stamp()

        try:
            put_card(film["project"], card)
        except RuntimeError as problem:
            say(f"  could not write its page: {problem}")
            trouble += 1

        # **A cover that will not draw is not a reason to fail a refresh.** It
        # needs a browser on this machine; the words do not, and the words are
        # what somebody is waiting for.
        try:
            n = put_cover(film["project"], film["title"], card)
            if n:
                say(f"  {n} link cover{'' if n == 1 else 's'} redrawn")
        except (RuntimeError, OSError) as problem:
            say(f"  its link covers could not be drawn: {problem}")
            continue
        c = card["counts"]
        def many(n, word):
            return f"{n} {word}{'' if n == 1 else 's'}"
        say(f"  {many(c['scenes'], 'scene')}, {many(c['shots'], 'shot')}, "
            f"{many(c['locations'], 'location')}, {many(c['days'], 'day')}"
            f" — your-domain.example/f/{film['project']}")

    # **The portals with no film behind them**, the same words and covers,
    # nothing of a film. Their id is their Notion page, so there is nothing
    # to look up; a run with no token was told above and skips them.
    for portal in portals if key else []:
        say(f"\n{portal['title']}")
        card = card_now(portal["project"])
        before = json.dumps(card, sort_keys=True)
        was = {"documents": len(card.get("documents", [])), "crew": len(card.get("crew", []))}
        card.setdefault("version", 1)
        trouble += words_from_notion(card, portal["project"], "link", key, portal["project"], was)
        # A portal's id is its project's page id: the record is the same one.
        took = from_record(card, *record_view(portal["project"]))
        if took:
            say(f"  from the project record: {', '.join(took)}")
        if json.dumps(card, sort_keys=True) == before:
            say("  nothing had changed")
        card["updated"] = stamp()
        try:
            put_card(portal["project"], card)
        except RuntimeError as problem:
            say(f"  could not write its page: {problem}")
            trouble += 1
            continue
        try:
            n = put_cover(portal["project"], portal["title"], card)
            if n:
                say(f"  {n} link cover{'' if n == 1 else 's'} redrawn")
        except (RuntimeError, OSError) as problem:
            say(f"  its link covers could not be drawn: {problem}")
        say(f"  a portal with no film — your-domain.example/f/{portal['project']}")

    say("\nDone." if not trouble else f"\nDone, with {trouble} problem(s) above.")
    return 1 if trouble else 0


if __name__ == "__main__":
    sys.exit(main())
