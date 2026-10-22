#!/usr/bin/env python3
"""What he chose — the deck's arrangement, in the only terms that survive.

His ruling, 2026-09-05: *"it's never about one exact design or template... You
have to be adaptable and change."* The old `deck.json` stored **where things
landed** — three pictures in this row, page 2, a 7.35in budget. That is a design
decision buried in the plumbing, and it is why every deck would come out as the
same deck in different colours: rewrite the design and every choice he made is
thrown away with it.

This stores **what he chose** instead:

    a section  ->  groups, in order
    a group    ->  pictures, in order, and how much it matters

Nothing here knows about inches, pages, or how many fit across. Those are
formatting, they differ between paper and web, and each renderer decides them
from the emphasis it is given. That is the whole reason his arrangement can
outlive a redesign, and the reason the hero on page 2 of the PDF can stay a hero
on the website instead of becoming one of twelve identical cells.

**Three layers**, his correction the same day. Notion owns content and order.
*Which picture, what belongs with what, what is emphasised* is global and lives
here. *Sizes, how many across, page breaks, crop* are per side and live in the
renderers.
"""

import json
from pathlib import Path

VERSION = 1

# How much a group matters, loudest first. A renderer maps these onto its own
# medium — a hero is a whole sheet on paper and a full-width plate on a screen,
# and neither number is stored here.
EMPHASIS = ["hero", "large", "normal", "quiet"]

# What a row of N pictures used to mean, when packing was the only language
# available. This is the migration, not a rule: a lone picture on a row was
# always somebody saying *this one carries the page*.
FROM_ROW_LENGTH = {1: "hero", 2: "large", 3: "normal"}


def emphasis_of_row(row):
    return FROM_ROW_LENGTH.get(len(row), "quiet")


class Group:
    """Pictures that belong together. A row on paper, a row on a screen."""

    #: What this class models. Anything else on a group is carried, not read.
    OWN = ("pictures", "emphasis", "ratio", "across")

    def __init__(self, pictures, emphasis="normal", ratio="", across=None, rest=None):
        self.pictures = list(pictures)
        self.emphasis = emphasis if emphasis in EMPHASIS else "normal"
        # **How many sit across is his, and it is per side.** The editor writes
        # `across: {"paper": 3, "web": 2}` when he sets it, and `bands()` in
        # deck.js reads it in preference to the emphasis default. Since the
        # portal started printing the PDF itself this is not a preview setting
        # — it decides the printed page.
        self.across = dict(across or {})
        # **Everything this class has not heard of, kept anyway.** A publish
        # from the Mac rebuilds the portal's record out of these objects, so a
        # key the model does not know is a key the publish deletes. That is how
        # `across` was being erased from every group, silently, on both sides at
        # once — and it would have been the same story for the next per-side
        # setting the editor grows. The round trip is lossless now; only the
        # values below are *understood*.
        self.rest = dict(rest or {})
        # **A grid, rather than a row of true shapes.** A band normally gives
        # each frame width in proportion to its own shape, so a row is ragged by
        # design. A group that names a ratio is drawn as even cells cropped to
        # it — which is what a contact grid is, and what he asked the top of his
        # bible to be.
        self.ratio = ratio

    @property
    def loudness(self):
        return EMPHASIS.index(self.emphasis)

    def as_json(self):
        d = dict(self.rest)
        d.update({"emphasis": self.emphasis, "pictures": self.pictures})
        if self.ratio:
            d["ratio"] = self.ratio
        if self.across:
            d["across"] = self.across
        return d

    @staticmethod
    def of_json(d):
        return Group(d.get("pictures", []), d.get("emphasis", "normal"),
                     d.get("ratio", ""), d.get("across"),
                     {k: v for k, v in d.items() if k not in Group.OWN})


class Section:
    """One part of the deck. Either words, or pictures, or both."""

    OWN = ("id", "title", "on", "groups")

    def __init__(self, id, title="", on=True, groups=None, rest=None):
        self.id = id
        self.title = title
        self.on = on
        self.groups = list(groups or [])
        self.rest = dict(rest or {})      # carried, for the reason above

    @property
    def pictures(self):
        return [k for g in self.groups for k in g.pictures]

    def as_json(self):
        d = dict(self.rest)
        d.update({"id": self.id, "on": self.on})
        if self.title:
            d["title"] = self.title
        if self.groups:
            d["groups"] = [g.as_json() for g in self.groups]
        return d

    @staticmethod
    def of_json(d):
        return Section(d["id"], d.get("title", ""), d.get("on", True),
                       [Group.of_json(g) for g in d.get("groups", [])],
                       {k: v for k, v in d.items() if k not in Section.OWN})


class Arrangement:
    def __init__(self, sections=None, film="", page=""):
        self.sections = list(sections or [])
        self.film = film
        self.page = page

    @property
    def live(self):
        return [s for s in self.sections if s.on]

    @property
    def pictures(self):
        return [k for s in self.live for k in s.pictures]

    def as_json(self):
        return {"version": VERSION, "film": self.film, "page": self.page,
                "sections": [s.as_json() for s in self.sections]}

    def save(self, path):
        Path(path).write_text(json.dumps(self.as_json(), indent=1) + "\n")

    @staticmethod
    def load(path):
        d = json.loads(Path(path).read_text())
        return Arrangement([Section.of_json(s) for s in d.get("sections", [])],
                           d.get("film", ""), d.get("page", ""))


# ---------------------------------------------------------------------------
# Reading what he already arranged
# ---------------------------------------------------------------------------

def from_packed(deck_json, theme=None, film="", page=""):
    """Recover his intent from a packed `deck.json`.

    **The intent was always in there**, expressed in the only language the old
    format had. A row is a group — pictures the editor was told to keep on one
    line. A row of one, where its neighbours hold three and four, is a picture
    he gave a whole band to. Page boundaries are dropped on the floor, which is
    the point: they are paper's business and they are re-decided at render.

    His `deck.json` keeps two lists that have to be woven back together. The
    `sections` list is the real order of the deck and holds both words sections
    (`dogma`) and picture sections (`__p_opening__`). `projects` holds the
    pictures, keyed by a bare slug (`opening`). So the marker is unwrapped to
    find its pictures, and a section with no pictures is a section of words.
    """
    labels = (theme or {}).get("section_labels", {})
    by_slug = {p["slug"]: p for p in deck_json.get("projects", [])}
    out = []
    for entry in deck_json.get("sections", []):
        sid = entry.get("id", "")
        on = entry.get("on", True)
        slug = sid[4:-2] if sid.startswith("__p_") and sid.endswith("__") else None
        project = by_slug.get(slug) if slug else None
        if project is None:
            out.append(Section(sid, labels.get(sid, ""), on))
            continue
        groups = []
        for pg in project.get("pages", []):
            for row in pg:
                row = [k for k in row if k]
                if row:
                    groups.append(Group(row, emphasis_of_row(row)))
        # **The theme's own label first, the folder name only as a fallback.**
        # A project's title here is its slug — `overall_approach_b` — which is a
        # folder name and not a name, and it went straight into the editor's
        # jump list. The theme names these sections properly; the `— frames`
        # it appends is for a print contents page and is not part of the name.
        named = labels.get(sid, "").split(" \u2014 frames")[0]
        out.append(Section(slug, named or project.get("title") or "", on, groups))
    return Arrangement(out, film, page)


# ---------------------------------------------------------------------------
# What each medium makes of it
# ---------------------------------------------------------------------------

# How wide a group of a given loudness wants to be, per medium — a *ceiling* on
# how many pictures share a band, not a promise. Paper can hold four across on
# an 8.5in sheet; a phone cannot, and his own rule of 2026-09-05 was *"for the
# html version avoid tall photos completely, and never crop images super
# skinny."* This table is the whole of the difference, and it lives here rather
# than in the stored arrangement because it is formatting.
# **The same rows the page he wrote has.** They differed: the web capped a quiet
# group at three, so a row of four became two and two — bigger frames, and
# pictures sitting where neither his Notion page nor the printed deck puts them.
# His note, 2026-09-06: keep everything exactly in the order it is in Notion,
# and make the opening grid smaller. Both are the same answer — a row of four
# stays a row of four, which is smaller frames and his own placement.
ACROSS = {
    "paper": {"hero": 1, "large": 2, "normal": 3, "quiet": 4},
    "web":   {"hero": 1, "large": 2, "normal": 3, "quiet": 4},
}


def bands(section, medium="paper"):
    """A group, split into bands of at most what this medium allows across.

    A group is *what belongs together*; a band is a line of pictures. They are
    usually the same thing. They differ when a group is wider than the medium
    can carry — four across is fine on a sheet and cramped on a screen — and
    then the group breaks into more than one band rather than shrinking below
    what a frame can be read at.
    """
    cap = ACROSS[medium]
    out = []
    for g in section.groups:
        most = max(1, cap.get(g.emphasis, 3))
        keys = g.pictures
        if len(keys) <= most:
            out.append((keys, g.emphasis))
            continue
        # **Split evenly, never greedily.** Taking `most` at a time leaves the
        # remainder on a line of its own — four across becomes three and a
        # stray, and a lone picture is drawn full width. That is precisely the
        # fault he named on 2026-09-05: *"make sure that there's not really a
        # lot of awkward blank space between images"*. Decide how many lines
        # first, then divide the pictures between them.
        lines = -(-len(keys) // most)
        # **Never a line of one.** His rule, 2026-09-06: no single-image rows.
        # Three across a cap of two balances to two and one, which strands the
        # third; one line fewer holds them together and is a row slightly wider
        # than the cap rather than a picture on its own.
        while lines > 1 and len(keys) - most * (lines - 1) == 1:
            lines -= 1
        at = 0
        for i in range(lines):
            take = -(-(len(keys) - at) // (lines - i))
            out.append((keys[at:at + take], g.emphasis))
            at += take
    return out
