#!/usr/bin/env python3
"""Do a deck's two designs still say the same thing?

    python3 twin.py <deck-folder> [<deck-folder> ...]

A deck has two designs — `template.html` for the press and `web.html` for the
portal — and they are edited separately on purpose. `decks/PRINT-AND-WEB.md` is
the list of what they are allowed to be separate *about*: eight things the
medium decides, and nothing else. The first of the eight ends with the one line
this program exists to enforce:

    the two files are allowed to disagree about how finely the sections are
    cut. They are not allowed to disagree about what the sections say.

Nothing checks that today, and nothing can catch it by eye: a paragraph added to
the printed bible and not to the web one is invisible until somebody reads both
documents side by side, which nobody does. It shows up months later as a page on
the website that is quietly missing a sentence the PDF has.

**The words are the `data-t` keys.** Every editable string in either design
carries one, and `text.md` holds what it says. So two designs saying the same
thing means: the same set of keys, and a word in `text.md` for each. Which
section a key sits in, and how many sections there are, is not checked — that is
rule 1, and it is allowed to differ.

**One exception, and it is rule 6.** A PDF is emailed and opened months later
with nothing around it, so it opens with a cover; a page on the portal is
reached through the film and arrives already named, so it has none. Keys under
`cover.` are therefore allowed to be print-only. Nothing else is.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from text_io import parse_markdown  # noqa: E402

KEY_RE = re.compile(r'data-t="([^"]+)"')

#: Rule 6. A cover belongs to the printed document and to nothing else.
PRINT_ONLY = ("cover.",)


def keys_in(path):
    return set(KEY_RE.findall(path.read_text())) if path.exists() else set()


def sections_in(path):
    return (re.findall(r"<!--SECTION:([a-z_]+)-->", path.read_text())
            if path.exists() else [])


def check(folder):
    """Returns (faults, wrong, notes).

    `wrong` is what somebody has to fix; `notes` is everything else worth
    saying. They are kept apart because `render.py` prints only the first —
    after a print has already succeeded, a count of how many sections each side
    has is noise, and a missing paragraph is not.
    """
    folder = Path(folder)
    print_design, web_design = folder / "template.html", folder / "web.html"
    words_file = folder / "text.md"
    out, notes, faults = [], [], 0

    for f in (print_design, web_design):
        if not f.exists():
            notes.append(f"  no {f.name} — nothing to compare")
            return 0, out, notes

    on_paper, on_web = keys_in(print_design), keys_in(web_design)
    words = parse_markdown(words_file.read_text()) if words_file.exists() else {}

    missing_web = {k for k in on_paper - on_web
                   if not k.startswith(PRINT_ONLY)}
    missing_paper = on_web - on_paper

    if missing_web:
        faults += len(missing_web)
        out.append(f"  {len(missing_web)} in the print design and not on the web:")
        out += [f"      {k}" for k in sorted(missing_web)]
    if missing_paper:
        faults += len(missing_paper)
        out.append(f"  {len(missing_paper)} on the web and not in the print design:")
        out += [f"      {k}" for k in sorted(missing_paper)]

    # **A key with no words is a hole on the page**, and it is drawn as nothing
    # at all rather than as an error, which is why it survives a proof-read.
    used = on_paper | on_web
    blank = {k for k in used if not (words.get(k) or "").strip()}
    if blank:
        faults += len(blank)
        out.append(f"  {len(blank)} with no words in text.md — these draw empty:")
        out += [f"      {k}" for k in sorted(blank)]

    # Not a fault: words nobody draws. Usually a section switched off, which is
    # his to decide, and deleting them is never this program's business.
    spare = {k for k in words if k not in used}
    if spare:
        notes.append(f"  {len(spare)} in text.md that neither design uses "
                     f"(nothing to fix; a section may just be off)")

    cover = {k for k in on_paper - on_web if k.startswith(PRINT_ONLY)}
    paper_secs, web_secs = sections_in(print_design), sections_in(web_design)
    notes.append(f"  {len(used)} words, {len(paper_secs)} sections in print and "
                 f"{len(web_secs)} on the web (rule 1 — allowed to differ)")
    if cover:
        notes.append(f"  {len(cover)} cover words, print only (rule 6)")
    return faults, out, notes


def main():
    folders = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not folders:
        raise SystemExit("usage: twin.py <deck-folder> [<deck-folder> ...]")
    bad = 0
    for f in folders:
        print(Path(f).name)
        faults, wrong, notes = check(f)
        print("\n".join(wrong + notes))
        print("  the two designs say the same thing" if not faults
              else f"  {faults} to fix")
        bad += faults
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
