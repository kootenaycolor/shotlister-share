#!/usr/bin/env python3
"""The press — his Mac, printing a deck when the deck changes.

    python3 press.py [--once] [--quiet]

His plan of 2026-09-05: *"your Mac is the press."* Making a beautiful PDF wants
his real typefaces and a real browser, and a worker has neither — so the deck
lives on the portal and the printing happens here. This is the half that makes
that automatic: it watches every deck it knows about, and when one has been
changed on the portal it pulls the change down, prints it, and puts the PDF back
under the film's Documents.

**Why it has to do more than call `render.py`.** The editor changes the deck's
*record* — words, order, grouping, emphasis — while `render.py` prints from
`deck.json`, which is the old packed shape: rows already chosen, pages already
decided. Left alone, a change made in the editor would reach the website and
never reach the PDF. So this converts one into the other first, deciding the
paper formatting from the emphasis exactly as `arrangement.bands` does for a
screen, and letting `flow_pages` fill the sheets.

**It never invents and never destroys.** A deck it has no local folder for is
skipped and said, not created. A record it cannot read leaves the last printed
PDF exactly where it was.
"""

import json
import tempfile
import hashlib
import re
import subprocess
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from arrangement import Arrangement, Section, Group, bands  # noqa: E402
from deckcore import Deck, load_dims, flow_pages  # noqa: E402
import publish  # noqa: E402
from bible import project_for  # noqa: E402

SEEN = Path.home() / "Library/Application Support/deck-builder/printed.json"
REGISTRY = Path.home() / "Library/Application Support/deck-builder/decks.json"

QUIET = False


def say(*a):
    if not QUIET:
        print(*a, flush=True)


def seen():
    try:
        return json.loads(SEEN.read_text())
    except (OSError, ValueError):
        return {}


def remember(key, stamp):
    was = seen()
    was[key] = stamp
    SEEN.parent.mkdir(parents=True, exist_ok=True)
    SEEN.write_text(json.dumps(was, indent=1))


def decks():
    """Every deck folder that says which film it belongs to."""
    try:
        listed = json.loads(REGISTRY.read_text())
    except (OSError, ValueError):
        return []
    out = []
    for one in listed:
        folder = Path(one.get("path", ""))
        cfg = folder / "bible.json"
        if not folder.is_dir() or not cfg.exists():
            continue
        try:
            said = json.loads(cfg.read_text())
        except ValueError:
            continue
        if said.get("film"):
            out.append((one.get("name", folder.name), folder, said))
    return out


def as_markdown(words):
    """The record's words as `text.md` — one writer, kept in `text_io`."""
    from text_io import words_markdown
    return words_markdown(words)


def packed_from(record, deck):
    """The record, in the shape `render.py` prints from.

    **Paper decides its own formatting**, his three layers: what is emphasised
    is his and reaches both outputs; how many sit across on a sheet is paper's
    business. `bands` reads the same table the editor uses, and `flow_pages`
    fills the sheets from the row heights.
    """
    arr = Arrangement([Section.of_json(s) for s in record.get("sections", [])])
    _groups, paths, _labels = deck.scan()
    dims = load_dims({k: s for k, s in paths.items() if k in set(arr.pictures)})
    shape = {k: (wh[0] / wh[1] if wh and wh[1] else 16 / 9) for k, wh in dims.items()}

    projects, sections = [], []
    for one in arr.sections:
        if not one.groups:
            sections.append({"id": one.id, "on": one.on})
            continue
        rows = [b for b, _loud in bands(one, "paper")]
        rows = [[k for k in r if k in shape] for r in rows]
        rows = [r for r in rows if r]
        pages = flow_pages(rows, shape, deck.page_w - 2 * deck.gap, deck.gap,
                           deck.first_budget, deck.cont_budget) if rows else []
        sections.append({"id": f"__p_{one.id}__", "on": one.on})
        projects.append({"slug": one.id, "title": one.title or one.id,
                         "credit": "", "pages": pages})
    return {"version": 7, "sections": sections, "cover": [], "projects": projects}



def printed_sheets(project, slug, deck, record):
    """The sheets the editor published, made into a document Chrome can print.

    **The end of two packers.** `packed_from` below decides where pictures land
    on paper by measuring inches — and so does the editor, differently, which is
    Ref 789: the first sheet the press made was arranged differently from what
    he was looking at until he published once. Now the editor draws the sheets
    and this prints them. Nothing is decided twice.

    Returns the built file, or None if this deck has never published a paper
    side — in which case the old road is taken and nothing changes for it.
    """
    got = subprocess.run(publish.wrangler() + [
        "r2", "object", "get", f"{publish.BUCKET}/p/{project}/decks/{slug}.paper.html",
        "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout.strip():
        return None
    body = got.stdout.decode("utf-8", "replace")
    # **The design's own head, off the deck folder.** The sheets carry no
    # stylesheet — only the body publishes — so the print template's `<style>`
    # and its `@font-face` rules are put back around them here, from the same
    # file `paper_kit` sent up. His real typefaces are on this Mac, which is
    # the whole reason the press is here.
    tpl = deck.template.read_text()
    head = tpl.split("</head>")[0] + "</head><body>" if "</head>" in tpl else "<html><head></head><body>"
    # **A picture is beside the film on the portal; here it is in
    # `build/img/portal/`, where `pictures_for_print` puts it.** The document is
    # printed from `build/`, so the address is relative to that — it used to
    # climb two folders and land outside the deck, and the first sheets the
    # press printed from the editor came out with every frame empty
    # (2026-09-07, a 1.5 MB bible).
    body = re.sub(r'(\s(?:src|href)=")pic/', r'\1img/portal/', body)
    out = deck.build_dir / "sheets.html"
    out.write_text(head + body + "</body></html>")
    return out


def pictures_for_print(project, deck, record):
    """Pull down every picture the sheets point at, so Chrome can draw them."""
    into = deck.build_dir / "img" / "portal"
    into.mkdir(parents=True, exist_ok=True)
    want = {held.get("name") for held in (record.get("pictures") or {}).values() if held.get("name")}
    for name in want:
        at = into / name
        if at.exists() and at.stat().st_size:
            continue
        got = subprocess.run(publish.wrangler() + [
            "r2", "object", "get", f"{publish.BUCKET}/p/{project}/docs/{name}",
            "--pipe", "--remote"], capture_output=True)
        if got.returncode == 0 and got.stdout:
            at.write_bytes(got.stdout)
    return into



# **Notion, over the same road `hub/refresh.py` takes.** The portal holds no
# Notion token by design — it is a Cloudflare Worker serving a public site — so
# a pull is *asked for* in the editor and *done here*, on the Mac that already
# has his token in the keychain. That is the whole answer to "how does the deck
# know which Notion page": it is written on the record, once, and this reads it.
sys.path.insert(0, str(TOOLS.parent.parent / "hub"))


def notion_page_id(url):
    """The page id out of a Notion address, however it was copied."""
    bare = re.sub(r"[?#].*$", "", str(url or ""))
    found = re.findall(r"([0-9a-fA-F]{32}|[0-9a-fA-F-]{36})", bare)
    if not found:
        return ""
    last = found[-1].replace("-", "")
    if len(last) != 32:
        return ""
    return f"{last[0:8]}-{last[8:12]}-{last[12:16]}-{last[16:20]}-{last[20:]}"


def notion_pictures(page_id, key):
    """Every picture on that page, as bytes, in the order they appear.

    **Downloaded, never linked.** A picture on a Notion page is served from a
    signed address that expires within the hour, so a link makes a page that
    works while you are looking at it and is broken by the afternoon.
    """
    import refresh                                          # noqa: PLC0415
    out = []
    cursor = None
    for _ in range(20):
        at = f"blocks/{page_id}/children?page_size=100" + (f"&start_cursor={cursor}" if cursor else "")
        said = refresh.notion(at, key=key)
        for block in said.get("results", []):
            if block.get("type") != "image":
                continue
            held = block["image"]
            where = (held.get("file") or held.get("external") or {}).get("url", "")
            if not where:
                continue
            got = subprocess.run(["curl", "-sL", "--max-time", "60", where], capture_output=True)
            if got.returncode == 0 and got.stdout:
                out.append(got.stdout)
        if not said.get("has_more"):
            break
        cursor = said.get("next_cursor")
    return out


def pull_pictures(project, deck_name, record):
    """Do what the editor asked for: put Notion's pictures on the film.

    Stored content-addressed, the same bargain every picture on the portal
    strikes, so the same picture pulled twice costs nothing and makes one copy.
    Returns the names, newest last, or None if it could not be done.
    """
    import refresh                                          # noqa: PLC0415
    said = record.get("notion") or {}
    page_id = notion_page_id(said.get("url"))
    if not page_id:
        say(f"  {deck_name}: its Notion link is not a page address")
        return None
    key = refresh.token()
    if not key:
        say(f"  {deck_name}: no Notion token on this Mac — nothing pulled")
        return None
    try:
        found = notion_pictures(page_id, key)
    except Exception as e:                                   # noqa: BLE001
        say(f"  {deck_name}: Notion would not answer — {e}")
        return None
    names = []
    for data in found:
        name = hashlib.sha256(data).hexdigest()[:32] + ".jpg"
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            f.write(data)
            where = f.name
        try:
            put = subprocess.run(publish.wrangler() + [
                "r2", "object", "put", f"{publish.BUCKET}/p/{project}/docs/{name}",
                "--file", where, "--remote", "--content-type", "image/jpeg"],
                capture_output=True, text=True)
        finally:
            Path(where).unlink(missing_ok=True)
        if put.returncode == 0:
            names.append(name)
    return names


def do_pulls(project, slug, deck_name, record):
    """Act on anything the editor asked for, and take the note back off."""
    asked = record.get("pull") or []
    if not asked:
        return False
    fresh = []
    if "pictures" in asked:
        got = pull_pictures(project, deck_name, record)
        if got is None:
            return False
        fresh = got
        say(f"  {deck_name}: pulled {len(fresh)} picture{'' if len(fresh) == 1 else 's'} from Notion")
    record.pop("pull", None)
    if fresh:
        record["fresh"] = sorted(set([*(record.get("fresh") or []), *fresh]))
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(record, f)
        where = f.name
    try:
        subprocess.run(publish.wrangler() + [
            "r2", "object", "put", f"{publish.BUCKET}/p/{project}/decks/{slug}.json",
            "--file", where, "--remote",
            "--content-type", "application/json; charset=utf-8"], capture_output=True)
    finally:
        Path(where).unlink(missing_ok=True)
    return True


def print_one(name, folder, cfg):
    """Pull a deck down, print it, and file the PDF. True if it printed."""
    slug = cfg.get("page", "bible")
    project = project_for(cfg["film"])
    if not project:
        say(f"  {name}: no film called {cfg['film']} on the portal")
        return False
    got = subprocess.run(publish.wrangler() + [
        "r2", "object", "get", f"{publish.BUCKET}/p/{project}/decks/{slug}.json",
        "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout:
        # **An empty read is not an empty deck.** A signed-out wrangler writes
        # its error to stderr and nothing to stdout, and treating that as "no
        # record" would print the deck from a stale local copy every run.
        say(f"  {name}: could not read its record — left alone")
        return False
    try:
        record = json.loads(got.stdout)
    except ValueError:
        say(f"  {name}: its record is not readable — left alone")
        return False

    # **What he asked for in the editor, before anything is printed.** The
    # portal cannot reach Notion; this Mac can, so a pull is asked for there and
    # done here. It is taken off the record once it is done, so it happens once.
    try:
        do_pulls(project, slug, name, record)
    except Exception as e:                                   # noqa: BLE001
        say(f"  {name}: could not do what the editor asked — {type(e).__name__}: {e}")

    key = f"{project}/{slug}"
    stamp = record.get("updated", "")
    if not stamp or seen().get(key) == stamp:
        return False

    say(f"  {name}: changed {stamp} — printing")
    deck = Deck(folder)
    # The words, back into the one file that owns them.
    if record.get("words"):
        folder.joinpath("text.md").write_text(as_markdown(record["words"]))
    # The arrangement, in both shapes: his, and the one the press prints from.
    Arrangement([Section.of_json(s) for s in record.get("sections", [])],
                cfg["film"], slug).save(folder / "arrangement.json")
    deck.deck_file.write_text(json.dumps(packed_from(record, deck), indent=1))

    # **What he arranged, if he has arranged it.** A deck whose paper side has
    # been published prints exactly those sheets; one that never has falls back
    # to the old road, so nothing that worked yesterday stops working.
    sheets = None
    try:
        pictures_for_print(project, deck, record)
        sheets = printed_sheets(project, slug, deck, record)
    except (OSError, ValueError) as e:                      # noqa: BLE001
        say(f"  {name}: could not read its sheets ({e}) — packing them here instead")
    if sheets:
        made = subprocess.run([sys.executable, str(TOOLS / "render.py"), str(folder),
                               "--from", str(sheets)], capture_output=True, text=True)
    else:
        made = subprocess.run([sys.executable, str(TOOLS / "render.py"), str(folder)],
                              capture_output=True, text=True)
    if made.returncode != 0:
        say(f"  {name}: would not print — {made.stderr.strip()[:200]}")
        return False
    filed = publish.file_pdf(project, deck, record.get("name") or slug)
    say(f"  {name}: printed{f', and filed {filed} MB under Documents' if filed else ''}")
    remember(key, stamp)
    return True


def main():
    global QUIET
    QUIET = "--quiet" in sys.argv
    once = "--once" in sys.argv
    while True:
        found = decks()
        if not found:
            say("No deck folder here says which film it belongs to.")
        printed = 0
        for name, folder, cfg in found:
            try:
                printed += 1 if print_one(name, folder, cfg) else 0
            except Exception as e:                       # noqa: BLE001
                # **One sick deck must not stop the others.** This runs
                # unattended; a raise here would mean nothing prints again
                # until somebody notices.
                say(f"  {name}: {type(e).__name__} — {e}")
        if printed:
            say(f"{time.strftime('%Y-%m-%d %H:%M')} — printed {printed}")
        if once:
            return
        time.sleep(60)


if __name__ == "__main__":
    main()
