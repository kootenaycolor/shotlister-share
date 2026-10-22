#!/usr/bin/env python3
"""A screenplay as a PDF, laid out the way a screenplay actually is.

    python3 studio/fixtures/screenplay.py out.pdf

**Why this exists rather than a PDF checked into the repo, or `cupsfilter`.**
The engine decides what a line *is* from where it sits on the page — a cue is a
cue because it starts 2.2 inches into the text block — so a fixture is only a
fixture if its geometry is a real screenplay's. `cupsfilter` will turn a text
file into a PDF, and its columns come out at 6 points a character instead of
7.2, which puts dialogue where a parenthetical belongs and finds nobody who
speaks. This writes the PDF by hand at exactly 12pt Courier, 1.5" left margin,
and the trade's own indents, so what the engine reads back is what a script
looks like.

It is also plain text in a repo, which a checked-in PDF is not.
"""
import sys

# 12pt Courier: every glyph is 7.2 points wide, every line 12 points tall.
GLYPH = 7.2
LEADING = 12.0
LEFT = 108.0          # 1.5 inches
TOP = 720.0           # first baseline, 1 inch down from the top of US Letter
LINES_PER_PAGE = 55

# Characters in from the left of the text block. The trade's standard, and the
# same numbers `engine/src/printed.rs` reads columns off.
COLUMN = {"head": 0, "action": 0, "cue": 22, "dialogue": 10, "paren": 16}

SCRIPT = [
    ("head", "33   INT. COUNTY JAIL - DAY"),
    ("", ""),
    ("action", "ANYA waits at the desk. A GUARD slides a form across."),
    ("", ""),
    ("cue", "ANYA"),
    ("dialogue", "I have been here since six."),
    ("", ""),
    ("cue", "GUARD"),
    ("dialogue", "Sign at the bottom."),
    ("", ""),
    ("head", "34   EXT. CAR PARK - CONTINUOUS"),
    ("", ""),
    ("action", "She walks out into the light and finds the car."),
    ("", ""),
    # A bare room name under a scene — no INT/EXT, no number of its own. The
    # detector finds it, letters it under 34, and leaves it unticked.
    ("head", "BATHROOM."),
    ("", ""),
    ("action", "The door is open. Nobody has been in here for a week."),
    ("", ""),
    ("cue", "ANYA"),
    ("dialogue", "Nobody is coming for us."),
    ("", ""),
    ("head", "35   INT. PHARMACY - NIGHT"),
    ("", ""),
    ("action", "RYAN counts the till twice and gets a different number."),
    ("", ""),
    ("cue", "RYAN"),
    ("dialogue", "We close in ten."),
    ("", ""),
    # A scene the project does not have — the "new" one.
    ("head", "36   EXT. HIGHWAY - NIGHT"),
    ("", ""),
    ("action", "The car goes past, and keeps going."),
    ("", ""),
    ("cue", "ANYA"),
    ("dialogue", "Faster."),
    ("", ""),
    # The same person, wearing an extension. Regular merging folds this back
    # onto ANYA; None leaves it as somebody else. The Characters tab's Name
    # Merging control has nothing to show without it.
    ("cue", "ANYA (V.O.)"),
    ("dialogue", "We should have gone north."),
]


def escape(text):
    return text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


def pages_of(script):
    pages, page = [], []
    for kind, text in script:
        page.append((kind, text))
        if len(page) == LINES_PER_PAGE:
            pages.append(page)
            page = []
    if page:
        pages.append(page)
    return pages


def stream(page):
    out = []
    for row, (kind, text) in enumerate(page):
        if not text:
            continue
        x = LEFT + COLUMN.get(kind, 0) * GLYPH
        y = TOP - row * LEADING
        out.append("BT /F1 12 Tf 1 0 0 1 %.2f %.2f Tm (%s) Tj ET"
                   % (x, y, escape(text)))
    return "\n".join(out).encode("latin-1")


def build(path):
    pages = pages_of(SCRIPT)
    objects = []          # each entry is the object's bytes, 1-indexed
    page_ids = []

    # 1 catalogue, 2 page tree, 3 font, then a pair per page.
    font = b"<</Type/Font/Subtype/Type1/BaseFont/Courier>>"
    first_page_object = 4
    for at in range(len(pages)):
        page_ids.append(first_page_object + at * 2)

    kids = " ".join("%d 0 R" % i for i in page_ids)
    objects.append(b"<</Type/Catalog/Pages 2 0 R>>")
    objects.append(("<</Type/Pages/Kids[%s]/Count %d>>"
                    % (kids, len(pages))).encode("latin-1"))
    objects.append(font)

    for at, page in enumerate(pages):
        body = stream(page)
        objects.append((
            "<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]"
            "/Resources<</Font<</F1 3 0 R>>>>/Contents %d 0 R>>"
            % (page_ids[at] + 1)).encode("latin-1"))
        objects.append(b"<</Length " + str(len(body)).encode()
                       + b">>\nstream\n" + body + b"\nendstream")

    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for at, obj in enumerate(objects, start=1):
        offsets.append(len(out))
        out += ("%d 0 obj\n" % at).encode() + obj + b"\nendobj\n"

    start = len(out)
    out += ("xref\n0 %d\n" % (len(objects) + 1)).encode()
    out += b"0000000000 65535 f \n"
    for at in range(1, len(objects) + 1):
        out += ("%010d 00000 n \n" % offsets[at]).encode()
    out += ("trailer\n<</Size %d/Root 1 0 R>>\nstartxref\n%d\n%%%%EOF\n"
            % (len(objects) + 1, start)).encode()

    with open(path, "wb") as file:
        file.write(bytes(out))


def unnumber(script):
    """The same screenplay with the scene numbers taken off its headings.

    Most of the scripts he is handed are like this, and until 2026-08-22 a draft
    with no numbers anywhere imported as nothing at all.
    """
    out = []
    for kind, text in script:
        if kind == "head" and text[:1].isdigit():
            text = text.split(None, 1)[1] if " " in text else text
        out.append((kind, text))
    return out


# The same scene Daybreak's 54 is, printed at a different number — Ref 241.
# A draft where a scene has been renumbered is the only way to see that the
# import notices, and the words have to match the project's scene 54 closely
# enough that the engine will pair them.
RENUMBERED = [
    ("head", "60   INT. FIGHT VENUE - NIGHT"),
    ("", ""),
    ("action", "Milo and Felix walk in through the crowd."),
    ("", ""),
    ("action", "BRUNO is in the ring. Somebody is already bleeding."),
]

if __name__ == "__main__":
    where = sys.argv[1] if len(sys.argv) > 1 else "screenplay.pdf"
    if "--unnumbered" in sys.argv:
        SCRIPT = unnumber(SCRIPT)
    if "--renumbered" in sys.argv:
        SCRIPT = RENUMBERED
    build(where)
