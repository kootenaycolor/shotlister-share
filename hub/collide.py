#!/usr/bin/env python3
"""Class names the front of house shares with the app, listed and held.

Four faults in one afternoon, 2026-09-04, and all four were the same fault:

  `.fact`      the app's location card, wearing the record page's vitals cell
  `.sharebtn`  a background the front of house never set, so the app's stayed
  `.pane`      every panel of a storyboard strip given `height:100vh` and a
               second copy of a `view-transition-name` — his report, storyboards
               with more than one image format wrong
  `.sheet`     the script panel's paper handed to `<body>`: `white-space:pre-wrap`
               turned every newline in every template into a real line box, and
               the margin drew two white bars down the sides of his phone

`hub.css` was written first and names things plainly — `.doc`, `.who`, `.fact`,
`.pane`, `.topbar`. The front of house then reached for the same plain words.
Where `hub.css`'s rule is *unscoped* — a selector whose first compound is the
class itself, so it matches anywhere in the document — the two meet, and which
one wins is a question of source order that nobody wrote down.

The front of house's own names now carry `fh-`. This is the ratchet: the names
still shared are listed below, each because sharing it is what we want. Anything
else appearing is the fault above, arriving again.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent

# Shared on purpose. Each line is the reason.
FINE = {
    "fh2":      "the front of house's own frame; hub.css quiets its scrollbars by name",
    "empty":    "'nothing here' reads the same in both, and should",
    "spacer":   "flex:1, and there is one honest way to write that",
    "cardhead": "a title with something pushed to its right — the same idea, twice",
    "td":       "the record's cells are the app's cells; front.css adds nothing",
}

# **The third party.** A published deck is drawn inside `.fh2` with a design of
# its own, written by whoever made that deck — so the two stylesheets above are
# already in force over markup neither of them has ever seen. Same fault as the
# four of 2026-09-04, one party further out, and it cost a day on 2026-09-08:
# `.frames` laid every block of his photographs out sideways in a grey box,
# `.frow` gave every picture row a filter button's padding and hover, `.body`
# made the writing a flex row 64px wide on a phone, and `.rail` dressed every
# section heading as the navigation sheet.
#
# The cure each time is to name the element the rule actually means — the rail
# is only ever `<nav>`, a filter row only ever `<button>`, the frame strip only
# ever `<span>` — or to hold it inside `.app`, or behind `.fh-pane >`.
#
# Owed, not fine. These two still reach a document, and the cure is the `fh-`
# prefix the front of house already uses everywhere else. Held here so the list
# cannot grow quietly while it waits.
OWED = {
    "sub":  "front.css:.fh2 .sub — rename fh-sub; a deck's section subtitle is a <p class=sub> too",
    "note": "front.css:.fh2 .note — rename fh-note; same shape in a deck's writing",
}

def selectors(css: str):
    """Every selector in a stylesheet, comments gone."""
    for block in re.findall(r"([^{}]+)\{", re.sub(r"/\*.*?\*/", "", css, flags=re.S)):
        for sel in block.split(","):
            sel = sel.strip()
            if sel and sel[0] not in "@%":
                yield sel


def loose_classes(css: str) -> set:
    """Classes hub.css can apply anywhere — the ones that reach into our markup.

    `.frames .pane` cannot escape `.frames`, so it is not one of these; `.pane`,
    `.pane:hover` and `.pane > b` all can."""
    out = set()
    for sel in selectors(css):
        first = re.split(r"[\s>+~]", sel)[0]
        m = re.match(r"\.([A-Za-z][\w-]*)", first)
        if m:
            out.add(m.group(1))
    return out

def reaches_a_document(css: str) -> dict:
    """Rules that land on a published deck's own markup.

    A document is drawn inside `.madepage`, inside `.fh2`. So `.fh2 .foo` — one
    compound past the frame, nothing standing between — reaches it. `.fh2 .pcard
    .n` does not: `.pcard` is the scope, and a document using *that* would be its
    own clash. Element-qualified compounds (`nav.rail`, `dl.spec`) are exactly the
    cure, so they are not counted."""
    out = {}
    for sel in selectors(css):
        parts = [p for p in re.split(r"[\s>+~]+", sel) if p]
        if len(parts) != 2 or not parts[0].startswith(".fh2"):
            continue
        m = re.fullmatch(r"\.([A-Za-z][\w-]*)((?:\.|:)[\w()\.-]+)*", parts[1])
        if m:
            out.setdefault(m.group(1), sel)
    return out


def deck_words() -> set:
    """Class names a deck design uses. The generator is the one every new deck
    starts from; the references are designs written by hand, which is where the
    surprises live."""
    out = set()
    here = ROOT.parent / "decks"
    files = [here / "tools/web_design.py"] + sorted(here.glob("references/*/web.html"))
    for f in files:
        if not f.exists():
            continue
        t = f.read_text()
        for sel in selectors(t):
            for m in re.finditer(r"\.deckweb\s+([^,{]+)", sel):
                for part in re.split(r"[\s>+~]+", m.group(1).strip()):
                    mm = re.match(r"\.([A-Za-z][\w-]*)", part)
                    if mm:
                        out.add(mm.group(1))
        for attr in re.findall(r'class="([^"$`]*)"', t):
            out.update(x for x in attr.split() if x)
    out.discard("deckweb")
    return out


def classes_used(js: str) -> set:
    """Every literal class name in the markup. A name built from a variable is
    invisible here, which is a limit worth knowing rather than working around:
    the four faults were all written out in full."""
    out = set()
    for attr in re.findall(r'class="([^"$`]*)"', js):
        out.update(t for t in attr.split() if t)
    return out

def main() -> int:
    loose = loose_classes((ROOT / "public/hub.css").read_text())
    used = classes_used((ROOT / "src/pages.js").read_text())
    clash = sorted((used & loose) - set(FINE))
    if clash:
        print("front of house markup uses hub.css names that are not scoped:")
        for n in clash:
            print(f"  .{n} — prefix it fh-{n}, or add it to FINE in hub/collide.py "
                  f"with the reason sharing it is right")
        return 1
    # The same question again, asked of a party neither stylesheet wrote:
    # a published deck's own design, drawn inside `.fh2`.
    front = (ROOT / "public/front.css").read_text()
    reach = {n: f"hub.css:.{n}" for n in loose}
    reach.update({n: f"front.css:{sel}" for n, sel in reaches_a_document(front).items()})
    theirs = sorted((set(reach) & deck_words()) - set(OWED))
    if theirs:
        print("the portal's styling reaches into a published deck's own design:")
        for n in theirs:
            print(f"  .{n} — name the element it means (nav.rail, dl.spec), hold it "
                  f"inside .app, or put it behind .fh-pane >   [{reach[n]}]")
        return 1

    print(f"no unscoped collisions ({len(FINE)} names shared on purpose, "
          f"{len(OWED)} owed the fh- prefix)")
    for n, why in sorted(OWED.items()):
        print(f"  owed: .{n} — {why}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
