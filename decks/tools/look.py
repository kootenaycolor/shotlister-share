#!/usr/bin/env python3
"""A film's look, in one place, read by both of its designs.

**The look is the film's; the medium is not.** `decks/PRINT-AND-WEB.md` is the
list of the eight things a medium decides — pages against a scroll, one width
against every width, a ground of its own against the site's. Everything *else*
is the film's own: its colours, its typefaces, the size of a heading, whether it
has a progress mark at all. His ruling, 2026-09-08:

> *"The goal here is not to start from the Call Her Back design, but from the
> underlying differences between how one would design a PDF for any film
> (regardless of the content or the style of that film) versus HTML."*

So the two scaffolds — `bible_design.py` for the press, `web_design.py` for the
portal — hold no colours and no typefaces between them. They hold the medium.
The look comes from here, out of the film's own `theme.json`, and both read the
same values, so a scaffolded deck cannot start life with its two designs already
disagreeing about what colour anything is.

A `theme.json` that says nothing gets the defaults below: quiet, dark, and
deliberately nobody's. It is a starting point to be redesigned, not a house
style — the point is that it is *correct about the medium* on the first render,
so a thread can spend its time on the design instead of re-deriving page
arithmetic.
"""

import copy
import json
from pathlib import Path

#: Where a deck keeps the typeface files it prints with. Rule 7: print embeds.
FONT_DIR = "assets/fonts"

DEFAULTS = {
    # ---- colour -----------------------------------------------------------
    # `ground` is **print only**. Rule 4: a PDF carries its own paper and a web
    # page lands on the portal's, so the web design never paints a field.
    "ground": "#101014",
    "ink": "#E8E4DE",
    "accent": "#C9A227",
    "muted": "#8B8781",
    "rule": "rgba(232,228,222,.18)",

    # ---- type -------------------------------------------------------------
    # Two faces, because a document has two voices: the film's own (titles, the
    # one-line claim) and the instructions a crew reads on set. Both carry a
    # real fallback stack — rule 7, the web fetches and a fetch can fail.
    "display": {"file": "PlayfairDisplay.ttf", "italic": "PlayfairDisplay-Italic.ttf",
                "web": "Playfair Display", "fallback": "Georgia, serif"},
    "text": {"file": "RethinkSans-Regular.ttf", "italic": "RethinkSans-Italic.ttf",
             "web": "Rethink Sans", "fallback": "system-ui, sans-serif"},

    # ---- size -------------------------------------------------------------
    # **One size per role.** In print this is not a preference: a size change
    # invalidates every page budget after it (rule 1), so the roles are fixed
    # and named. The web takes these as the *upper* end of a fluid scale — rule
    # 2, where nothing may be sized to a width nobody knows.
    "sizes": {"title": 44, "claim": 16, "note": 10.5, "label": 8.5, "mark": 7.5},

    # ---- the sheet --------------------------------------------------------
    # Print only, all of it. `eye` is the one eyeline: how far down every sheet
    # a title starts. A title that moves from sheet to sheet is the single
    # thing that reads as amateur, and it is rule 3 — a printed page is entered
    # cold, so every sheet has to look like the same document.
    "eye_in": 1.22,
    "pad_in": 0.68,
    "foot_in": 0.78,
    "plate_in": 0.24,
}

#: Old themes name their colours here. Mapped so a deck written before `look`
#: existed still scaffolds with its own palette rather than the defaults.
FROM_COLORS = {"paper": "ground", "ink": "ink", "accent": "accent", "muted": "muted"}


def look_of(theme):
    """Every look value filled in: the film's where it said, defaults elsewhere."""
    out = copy.deepcopy(DEFAULTS)
    for old, new in FROM_COLORS.items():
        said = (theme.get("colors") or {}).get(old)
        if said:
            out[new] = said
    said = theme.get("look") or {}
    for k, v in said.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k].update(v)
        else:
            out[k] = v
    return out


def budgets(theme, look=None):
    """How many inches of a sheet are left for pictures, given the furniture.

    **This is rule 1 made arithmetic, and it is why the two scaffolds cannot
    share a number.** A sheet is a fixed rectangle: whatever the running mark,
    the eyeline and the foot take, the plates get the rest, and if the theme's
    budget and the design's padding disagree the last row simply runs off the
    bottom of the page. Deriving it here means a scaffolded deck's design and
    its `theme.json` are consistent on the first print rather than after
    somebody has measured.

    The web has no equivalent and asks for none.
    """
    look = look or look_of(theme)
    height = float((theme.get("page") or {}).get("height_in", 11.0))
    return round(height - float(look["eye_in"]) - float(look["foot_in"]), 4)


def page_of(theme):
    page = theme.get("page") or {}
    return (float(page.get("width_in", 8.5)), float(page.get("height_in", 11.0)),
            page.get("css_size", "letter"))


def font_faces(look, folder="", name_display="DP", name_text="TX"):
    """`@font-face` rules for the press — the files, from beside the deck.

    Rule 7: print embeds and cannot fail to arrive; a missing file here is why
    the `fallback` in each face is not decoration.
    """
    root = f"{folder.rstrip('/')}/" if folder else f"{FONT_DIR}/"
    out = []
    for face, name in ((look["display"], name_display), (look["text"], name_text)):
        if face.get("file"):
            out.append(f"@font-face{{font-family:{name};src:url('{root}{face['file']}');"
                       f"font-weight:400 900;font-style:normal}}")
        if face.get("italic"):
            out.append(f"@font-face{{font-family:{name};src:url('{root}{face['italic']}');"
                       f"font-weight:400 900;font-style:italic}}")
    return "\n".join(out)


def theme_look_block(theme):
    """The `look` a scaffolded theme is written with, so he can see and edit it.

    Written out in full rather than left to the defaults: a value he cannot see
    is a value he will not change, and this is the file that is meant to be the
    only place the two designs get their look from.
    """
    look = look_of(theme)
    return {k: look[k] for k in
            ("ground", "ink", "accent", "muted", "rule",
             "display", "text", "sizes", "eye_in", "pad_in", "foot_in", "plate_in")}


def of_deck(folder):
    """The look of a deck already on disk."""
    try:
        theme = json.loads((Path(folder) / "theme.json").read_text())
    except (OSError, ValueError):
        theme = {}
    return look_of(theme)
