#!/usr/bin/env python3
"""Where the decks are.

Decks do not live in one place. Most belong to a project, so they sit in that
project's folder in Drive, at

    projects/<slug>/1-creative/decks/<deck-name>/
        <name>_<date>.pdf     the current finished PDF
        z-archive/            older dated PDFs
        z-source/             every working file (designs, json, pictures,
                              build, launcher apps) -- a deck's registered
                              folder is this z-source one

(Since 2026-10-15. Drive holds the working files as an off-Mac copy, out of
sight.) A few decks are general and live under portfolio/outbound.
Rather than guess, the tool remembers every deck it has opened.

    ~/Library/Application Support/deck-builder/decks.json

A folder counts as a deck if it holds theme.json and deck.json. Opening one
registers it, so it appears in the launcher next time.
"""

import json
import sys
import time
from pathlib import Path

STORE = Path.home() / "Library/Application Support/deck-builder"
FILE = STORE / "decks.json"


def is_deck(folder) -> bool:
    p = Path(folder)
    return (p / "theme.json").exists() and (p / "deck.json").exists()


def load():
    try:
        entries = json.loads(FILE.read_text())
    except Exception:
        entries = []
    # Drop anything that has been moved or deleted.
    return [e for e in entries if is_deck(e["path"])]


def save(entries):
    STORE.mkdir(parents=True, exist_ok=True)
    FILE.write_text(json.dumps(entries, indent=2))


def register(folder, name=None):
    p = Path(folder).expanduser().resolve()
    if not is_deck(p):
        return None
    entries = [e for e in load() if e["path"] != str(p)]
    entries.append({
        "name": name or deck_name(p),
        "path": str(p),
        "last_opened": time.strftime("%Y-%m-%d %H:%M"),
    })
    entries.sort(key=lambda e: e["last_opened"], reverse=True)
    save(entries)
    return str(p)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        for e in load():
            print(f'{e["name"]}\t{e["path"]}')
    elif cmd == "add" and len(sys.argv) > 2:
        p = register(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
        print(p or "not a deck folder (needs theme.json and deck.json)")
    elif cmd == "paths":
        for e in load():
            print(e["path"])
    elif cmd == "names":
        for e in load():
            print(e["name"])


if __name__ == "__main__":
    main()


def deck_home(folder):
    """The folder a deck's finished PDF belongs in: the parent of `z-source`.
    None for a deck that is not laid out that way (portfolio/outbound decks)."""
    p = Path(folder).resolve()
    return p.parent if p.name == "z-source" else None


def file_pdf_home(pdf):
    """File a freshly printed PDF at the top of its deck's home folder.

    The print is made inside `z-source` (render.py writes beside the deck's
    files). The copy goes up to the deck's home as the current PDF; any other
    PDF already up there is *moved* (never deleted) into `z-archive/`.
    Returns the new path, or None when the deck is not in that layout.
    """
    import shutil
    pdf = Path(pdf)
    home = deck_home(pdf.parent)
    if not home:
        return None
    dst = home / pdf.name
    shutil.copy2(pdf, dst)
    old = [f for f in home.glob("*.pdf") if f.name != pdf.name]
    if old:
        arch = home / "z-archive"
        arch.mkdir(exist_ok=True)
        for f in old:
            target = arch / f.name
            if target.exists():
                target = arch / f"{f.stem}-{int(f.stat().st_mtime)}{f.suffix}"
            f.rename(target)
    return dst


def deck_name(folder):
    """A deck's name: its folder's, or -- for a `z-source` folder -- its home's."""
    p = Path(folder).resolve()
    return p.parent.name if p.name == "z-source" else p.name
