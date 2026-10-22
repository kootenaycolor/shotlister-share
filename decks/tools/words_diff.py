#!/usr/bin/env python3
"""What the portal says that this folder does not — read-only, before you publish.

**The trap this closes.** `publish.py` pushes `text.md` over the portal's words
and *then* reports what differed, so an edit he made in the editor is already
gone by the time the warning prints. The only safe order is to look first, and
until now there was no way to look that did not also overwrite something:
`refresh_from_portal` rewrites `text.md` and `sources.json` on its way past.

This asks the portal the same question `publish.py` asks, prints the answer, and
writes nothing at all.

    python3 tools/words_diff.py <deck folder>

It also ignores a difference that is only markup. `text.md` holds
`Call Her <em>Back</em>` where the portal holds `Call Her Back`; that pair was
reported as changed on every publish for a whole day, which is exactly how a
real warning gets ignored. Those are listed separately, and quietly.

Exit status is 1 when a real difference exists, so a script can stop on it.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from deckcore import Deck                      # noqa: E402
from text_io import parse_markdown             # noqa: E402
import publish                                 # noqa: E402


def plain(s):
    """The words, without the mark-up either side happens to carry."""
    s = re.sub(r"<[^>]+>", "", s or "")
    s = s.replace("&amp;", "&").replace("&nbsp;", " ")
    return re.sub(r"\s+", " ", s).strip()


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: words_diff.py <deck folder>")
    deck = Deck(sys.argv[1])
    import json
    from bible import project_for
    cfg = json.loads((deck.dir / "bible.json").read_text())
    project = project_for(cfg.get("film", ""))
    slug = cfg.get("page", "")

    mine = parse_markdown(deck.text_md.read_text()) if deck.text_md.exists() else {}
    if not mine:
        raise SystemExit("no text.md — nothing to compare.")

    try:
        theirs = publish.pull_words(project, slug, mine)
    except Exception as e:                       # noqa: BLE001
        raise SystemExit(f"could not ask the portal: {e}")

    real, cosmetic = {}, {}
    for key, up_there in (theirs or {}).items():
        (cosmetic if plain(up_there) == plain(mine.get(key, "")) else real)[key] = up_there

    # **Sections too.** His arrangement is on the record as well as his words,
    # and the portal lost the opening's 4:3 grid once without anybody seeing
    # it because only words were compared (2026-09-07).
    arranged = []
    try:
        record = publish.fetch_record(project, slug) or {}
        from arrangement import Arrangement, Section
        folder = [s.as_json() for s in Arrangement.load(deck.dir / "arrangement.json").sections]
        portal = [Section.of_json(s).as_json() for s in record.get("sections") or []]
        if portal and portal != folder:
            ids = {s["id"] for s in portal} | {s["id"] for s in folder}
            by_p = {s["id"]: s for s in portal}; by_f = {s["id"]: s for s in folder}
            arranged = sorted(i for i in ids if by_p.get(i) != by_f.get(i))
    except (OSError, ValueError, KeyError):
        pass

    if not real and not cosmetic and not arranged:
        print("Nothing differs. Safe to publish.")
        return 0

    if arranged:
        print(f"{len(arranged)} section(s) arranged differently on the portal: {', '.join(arranged)}")
        print("  publish.py takes the portal's arrangement first now; --from-folder would overwrite it.")

    if cosmetic:
        print(f"{len(cosmetic)} difference(s) of mark-up only — ignore:")
        for k in sorted(cosmetic):
            print(f"  {k}")

    if real:
        print(f"\n{len(real)} REAL difference(s). Publishing would overwrite these:\n")
        for k in sorted(real):
            print(f"  {k}")
            print(f"    portal:  {plain(real[k])[:160]}")
            print(f"    folder:  {plain(mine.get(k, ''))[:160]}\n")
        print("publish.py takes the portal's wording first now; --from-folder would overwrite it.")
        return 1
    return 1 if arranged else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
