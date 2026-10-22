#!/usr/bin/env python3
"""Make a film's visual bible into a deck this program can open.

    python3 bible.py <folder> --film "Call Her Back" [--page bible] [--from <deck>]

For a project's deck, <folder> is projects/<slug>/1-creative/decks/<deck-name>/z-source
(the working files; the finished PDF is filed one level up, older ones in z-archive/).

## What changed, and why

The first version of this made a folder of its own — `bible.json`, its own
template, its own printer — on the argument that a deck is an *arrangement* and
a bible is a *sequence*, and the two are different shapes.

His verdict, 2026-09-05: *"the visual language bible folder cannot be opened by
my Deck Editor program"*, and *"I need to design the deck for the projects and
then somehow translate that to a PDF and the HTML"*. Both halves of that say the
split was wrong. The editor is where he tunes copy, image order and size, and a
bible he cannot open there is a bible he cannot fix.

**So a bible is a deck.** It turns out to fit the model already there, with no
change to the editor at all:

- a deck's **pools** group images by folder — so each section of the bible gets
  a folder under `img/`, and each becomes a group the editor offers;
- a deck's **projects** are "a titled group of pictures arranged into rows on
  pages" — which is exactly what a section of a bible is;
- a deck's **text.md** keys words to `data-t` attributes — so the bible's prose
  arrives as ordinary deck copy, editable in the editor.

What this program does is scaffold that folder out of what the portal holds, so
there is something real to open. Afterwards it is a deck like any other:
`render.py` prints it, `replan.py` re-flows it, Deck Editor arranges it.

## What it will not do twice

**The template is written once and never regenerated.** It is the design, and
the design is his. A later `--pull` refreshes the words and the pictures and
says if the portal has grown a section the template has no place for; it does
not touch the layout.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

BUCKET = "shotlister"
# **The hub is a sibling now, not an address.** Until the fold of 2026-09-06
# this reached across to `~/Developer/shotlister/hub` by absolute path, which is
# how one expired Cloudflare login took down two programs at once and did it
# silently. It is the same repo, so it is the same tree.
HUB = Path(__file__).resolve().parents[2] / "hub"
TOOLS = Path(__file__).resolve().parent
# The films live in Documents, not iCloud Drive, since the relay began carrying
# them between devices (STATUS.md, "the films"). The old place is still read
# second, for a Mac that has not moved yet.
FILMS = next((p for p in (Path.home() / "Documents/Shotlister",
                          Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/Shotlister")
              if p.is_dir()), Path.home() / "Documents/Shotlister")
PROJECT_ID = re.compile(r"^[0-9a-f]{32}$")


def say(*a):
    print(*a, flush=True)


def wrangler():
    local = HUB / "node_modules/.bin/wrangler"
    return [str(local)] if local.exists() else ["npx", "--yes", "wrangler@4"]


def fetch(key, into=None):
    got = subprocess.run(wrangler() + ["r2", "object", "get", f"{BUCKET}/{key}",
                                       "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout:
        return None
    if into:
        Path(into).parent.mkdir(parents=True, exist_ok=True)
        Path(into).write_bytes(got.stdout)
    return got.stdout


def project_for(film):
    said = (film or "").strip()
    if PROJECT_ID.match(said):
        return said
    if not FILMS.is_dir():
        raise SystemExit("Cannot find the Shotlister films folder.")
    for folder in sorted(FILMS.iterdir()):
        if folder.suffix == ".shotlist" and said.lower() in folder.stem.lower():
            try:
                return json.loads((folder / "remote.json").read_text()).get("project", "")
            except (OSError, ValueError):
                raise SystemExit(f"{folder.stem} is not on the relay yet.")
    raise SystemExit(f"No film here called {said}.")


# ------------------------------------------------------ the page, in sections

def words_of(rich):
    return "".join(b.get("s", "") for b in rich or []).strip()


def section_id(name, taken):
    """**Letters and underscores only.** A template's sections are found
    with `<!--SECTION:([a-z_]+)-->` — a digit or a hyphen in there and the
    section simply does not exist as far as the editor is concerned, which reads
    as the deck being empty rather than as a bad name."""
    said = re.sub(r"[^a-z]+", "_", (name or "").lower()).strip("_") or "part"
    said = said[:24]
    out, n = said, 2
    while out in taken:
        out, n = f"{said}_{n}", n + 1
    taken.add(out)
    return out


def split(tree):
    """The page as sections: a heading, then everything under it.

    Anything before the first heading becomes an opening section, because a
    bible that starts with a wall of frames — his does — would otherwise lose
    them.
    """
    taken, out = set(), []
    cur = {"id": section_id("opening", taken), "name": "Opening", "blocks": []}
    for node in tree or []:
        if not isinstance(node, dict):
            continue
        if node.get("t") in ("h1", "h2"):
            name = words_of(node.get("r")) or "Part"
            if cur["blocks"]:
                out.append(cur)
            cur = {"id": section_id(name, taken), "name": name, "blocks": []}
            continue
        cur["blocks"].append(node)
    if cur["blocks"]:
        out.append(cur)
    return out


def pictures_of(blocks):
    """Every stored picture under a section, in the order it is used."""
    found = []

    def walk(nodes):
        for n in nodes or []:
            if isinstance(n, dict):
                if n.get("t") == "img" and n.get("src"):
                    found.append(n["src"])
                walk(n.get("k"))
    walk(blocks)
    seen, out = set(), []
    for f in found:
        if f not in seen:
            seen.add(f)
            out.append(f)
    return out


def prose_of(blocks):
    """A section's words: paragraphs and bullets, flattened in order.

    **Bullets are kept as bullets.** His Notion bible is mostly them, and
    turning them into prose here would be inventing sentences he did not write.
    What the template does with them is a design question, and design is not
    this program's business.
    """
    lines = []

    def walk(nodes, depth=0):
        for n in nodes or []:
            if not isinstance(n, dict):
                continue
            t = n.get("t")
            said = words_of(n.get("r"))
            if t == "p" and said:
                lines.append(("p", said, depth))
            elif t == "li" and said:
                lines.append(("li", said, depth))
            elif t in ("quote", "callout") and said:
                lines.append(("q", said, depth))
            elif t == "h3" and said:
                lines.append(("h", said, depth))
            walk(n.get("k"), depth + 1 if t == "li" else depth)
    walk(blocks)
    return lines


# ---------------------------------------------------------------- scaffolding

def pull(folder, film, page):
    project = project_for(film)
    raw = fetch(f"p/{project}/pages/{page}.json")
    if not raw:
        raise SystemExit(f"The portal has no page called {page} on {film}.")
    tree = json.loads(raw)
    (folder / "page.json").write_bytes(raw)
    sections = split(tree)
    say(f"{len(tree)} blocks, {len(sections)} sections.")

    got = 0
    # **What each local file is called on the portal, written down.**
    #
    # The published page points at `pic/<name>`, and the first version worked
    # that name out by stripping the ordering prefix off the local filename and
    # hoping. It was wrong — the folder held pictures from an older run under
    # different names, so every `src` on the published page was a name the
    # portal had never heard of, and the page came out with holes where the
    # frames should be. A note kept at the moment of pulling cannot drift.
    kept = {}
    for s in sections:
        wanted = pictures_of(s["blocks"])
        s["pictures"] = []
        for i, name in enumerate(wanted):
            out = folder / "img" / s["id"] / f"{i:02d}-{name}"
            kept[str(out.relative_to(folder))] = name
            if not out.exists():
                # `docs/` first: a picture put on a page on purpose lives there,
                # one the film already held lives in `media/`.
                if not any(fetch(f"p/{project}/{w}/{name}", out) for w in ("docs", "media")):
                    say(f"  missing: {name}")
                    continue
            s["pictures"].append(out.name)
            got += 1
    (folder / "img" / "portal.json").write_text(json.dumps(kept, indent=1) + "\n")
    say(f"{got} pictures, in {len([s for s in sections if s['pictures']])} folders.")
    return sections


def write_sources(folder, sections):
    """**A pool per bible, grouped by folder.** `deckcore.scan` already groups a
    pool's subfolders, so each section becomes a group the editor offers with no
    change to it."""
    (folder / "sources.json").write_text(json.dumps({
        "pools": [{
            "id": "bible",
            "label": "This film",
            "root": str(folder / "img"),
            "group_glob": "*",
            "file_glob": "*.*",
            "include": [s["id"] for s in sections if s["pictures"]],
            "titles": {s["id"]: s["name"] for s in sections},
        }]
    }, indent=2) + "\n")


def count_prose(blocks):
    n = {"p": 0, "b": 0, "q": 0, "sub": 0}
    for kind, _, _ in prose_of(blocks):
        n[{"p": "p", "li": "b", "q": "q", "h": "sub"}[kind]] += 1
    return n


def write_deck(folder, sections):
    """What is chosen and arranged. Rows of three to begin with; he re-flows it
    in the editor, or `replan.py` does it in one pass."""
    projects = []
    for s in sections:
        pics = s["pictures"]
        if not pics:
            continue
        from deckcore import key_for
        keys = [key_for(str(folder / "img" / s["id"] / p)) for p in pics]
        rows = [keys[i:i + 3] for i in range(0, len(keys), 3)]
        projects.append({"slug": s["id"], "title": s["name"], "credit": "",
                         "pages": [rows]})
    # **Words then frames, section by section.** `__projects__` would put every
    # word in the deck before every picture in it; `__p_<slug>__` places one
    # group where its own section ends. `render.py` grew that marker for this.
    order = [{"id": "cover", "on": True}]
    for s in sections:
        if any((s.get("counts") or {}).values()):
            order.append({"id": s["id"], "on": True})
        if s["pictures"]:
            order.append({"id": f"__p_{s['id']}__", "on": True})
    (folder / "deck.json").write_text(json.dumps({
        "version": 1,
        "sections": order,
        "cover": [],
        "projects": projects,
    }, indent=2) + "\n")


def write_text(folder, sections, film):
    lines = [f"## {film} — Visual Bible", "", "### cover.title1", "", film, "",
             "### cover.sub1", "", "Visual Bible", ""]
    for s in sections:
        lines += [f"## {s['name']}", "", f"### {s['id']}.head1", "", s["name"], ""]
        n = {"p": 0, "li": 0, "q": 0, "h": 0}
        for kind, said, _ in prose_of(s["blocks"]):
            n[kind] += 1
            key = {"p": "p", "li": "b", "q": "q", "h": "sub"}[kind]
            lines += [f"### {s['id']}.{key}{n[kind]}", "", said, ""]
    (folder / "text.md").write_text("\n".join(lines) + "\n")


def write_theme(folder, film, sections, base=None):
    """The film's look and its page geometry, in the one file both designs read.

    **His own theme first, always.** This used to read the base deck's theme
    every time and write it out whole — so a later `--pull`, which anybody would
    expect to refresh the words and the pictures, silently threw away the page
    budgets and the palette he had tuned since. The folder's own file now wins
    over the base, and the base only fills a gap.

    **A fresh folder gets its budgets derived, not inherited.** How many inches
    of a sheet are left for frames depends on the furniture the design puts on
    it — the eyeline, the running mark, the foot — so a budget copied off
    another deck belongs to another design, and the last row runs off the page.
    `look.budgets` works it out from the same numbers `bible_design.py` lays the
    sheet with. On a folder that already has a theme, his numbers stand.
    """
    import look as look_mod
    from bible_design import TITH
    mine = folder / "theme.json"
    fresh = not mine.exists()
    if not fresh:
        theme = json.loads(mine.read_text())
    else:
        src = Path(base) / "theme.json" if base else TITH.parent / "theme.json"
        theme = json.loads(src.read_text()) if src.exists() else {}
    theme["look"] = {**look_mod.theme_look_block(theme), **(theme.get("look") or {})}
    if fresh:
        budget = look_mod.budgets(theme)
        grid = dict(theme.get("grid") or {})
        grid.update({"gap_in": look_mod.look_of(theme)["plate_in"],
                     "first_budget_in": budget, "cont_budget_in": budget,
                     "full_budget_in": budget})
        theme["grid"] = grid
    theme["name"] = "NR Bible"
    # The line along the foot of a page of frames. `render.py` defaults it to
    # "Selected work", which is a portfolio deck's phrase and reads as somebody
    # else's document on a film's bible.
    theme.setdefault("frames_foot", film)
    theme["file_stem"] = re.sub(r"[^A-Za-z0-9]+", "_", film).strip("_") + "_Visual_Bible"
    theme["section_labels"] = {"cover": "Cover",
                               **{s["id"]: s["name"] for s in sections},
                               **{f"__p_{s['id']}__": f"{s['name']} — frames"
                                  for s in sections if s["pictures"]}}
    theme.setdefault("project_notes", {})
    mine.write_text(json.dumps(theme, indent=2) + "\n")
    return theme


PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>{name}</string>
  <key>CFBundleIdentifier</key><string>com.example.{exe}</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>{exe}</string>
</dict></plist>
"""


def make_app(folder, name, script, extra=""):
    """The same shape `new_deck.py` uses, so every deck folder behaves alike."""
    import stat
    exe = name.replace(" ", "")
    app = folder / f"{name}.app"
    if app.exists():
        shutil.rmtree(app)
    (app / "Contents" / "MacOS").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_text(PLIST.format(name=name, exe=exe))
    run = app / "Contents" / "MacOS" / exe
    run.write_text("#!/bin/bash\n"
                   'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"\n'
                   f'exec /usr/bin/python3 "{TOOLS / script}" "$HERE" {extra} '
                   f'>> /tmp/nr-{exe}.log 2>&1\n')
    run.chmod(run.stat().st_mode | stat.S_IEXEC)


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    folder = Path(args[0]).expanduser().resolve()
    folder.mkdir(parents=True, exist_ok=True)
    if folder.name == "z-source":
        (folder.parent / "z-archive").mkdir(exist_ok=True)
    film = args[args.index("--film") + 1] if "--film" in args else ""
    page = args[args.index("--page") + 1] if "--page" in args else "bible"
    if not film and (folder / "bible.json").exists():
        film = json.loads((folder / "bible.json").read_text()).get("film", "")
    if not film:
        raise SystemExit("Say which film: --film 'Call Her Back'")
    (folder / "bible.json").write_text(json.dumps({"film": film, "page": page}, indent=2) + "\n")

    sys.path.insert(0, str(TOOLS))
    sections = pull(folder, film, page)
    for s in sections:
        s["counts"] = count_prose(s["blocks"])
    write_sources(folder, sections)
    base = args[args.index("--from") + 1] if "--from" in args else None
    theme = write_theme(folder, film, sections, base)
    fresh = not (folder / "deck.json").exists()
    if fresh:
        write_deck(folder, sections)
    else:
        say("deck.json is yours — left alone. Delete it to start the arrangement again.")
    write_text(folder, sections, film)

    # **The design is written once.** A later pull refreshes words and pictures
    # and says what is new; it never rewrites the layout.
    tpl = folder / "template.html"
    if not tpl.exists():
        from bible_design import template_for
        tpl.write_text(template_for(film, sections, theme))
        say("Wrote template.html — the design. Yours from here; nothing regenerates it.")
    else:
        have = set(re.findall(r"<!--SECTION:([a-z_]+)-->", tpl.read_text()))
        missing = [s["name"] for s in sections if s["id"] not in have and s["id"] != "opening"]
        if missing:
            say("The portal has sections your template has no place for: " + ", ".join(missing))

    # **The web template is its own file and its own question.** It was written
    # inside the `if the print template is missing` branch at first, so a folder
    # that already had a design never got one — and `publish.py` answered "this
    # deck has no web.html", which reads as the deck being wrong rather than the
    # scaffold having skipped a step.
    web = folder / "web.html"
    if not web.exists():
        import web_design
        web.write_text(web_design.template_for(film, sections, theme))
        say("Wrote web.html — the same design, for a browser. Also yours.")

    # Two things to double-click, because a command to remember is a chore.
    make_app(folder, "Rebuild PDF", "render.py")
    make_app(folder, "Preview Web", "publish.py", "--local")

    subprocess.run([sys.executable, str(TOOLS / "registry.py"), "add", str(folder)],
                   capture_output=True)
    say(f"Ready. Open it in Deck Editor, or: python3 tools/render.py '{folder}'")


if __name__ == "__main__":
    main()
