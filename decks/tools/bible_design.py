#!/usr/bin/env python3
"""The print half of a deck's design — a document made of sheets.

**What this used to be, and why it changed.** It copied the head and tail of one
approved pitch deck (`pitch-deck`) and wrote section bodies in that deck's class
names. That made a bible arrive looking like a deck he already liked, which was
the right instinct at the time and turned out to be the wrong mechanism: by
2026-09-08 not one of the nine classes it writes survived in his Call Her Back
bible. The design had been rebuilt by hand and none of it came back here, so the
next film would have started from a look nobody uses and had the whole thing
reinvented for it.

His ruling that day, when asked whether the difference between the two designs
could be built into the tools:

> *"The goal here is not to start from the Call Her Back design, but from the
> underlying differences between how one would design a PDF for any film
> (regardless of the content or the style of that film) versus HTML."*

**So this holds the medium, and nothing else.** Not a colour, not a typeface,
not a rule about progress marks — those come from the film's `theme.json`
through `look.py`, which its web counterpart reads too. What is written here is
the part of a printed document that is true whatever it looks like, and every
piece of it is one of the eight in `decks/PRINT-AND-WEB.md`:

  1  **Pages.** A sheet is a fixed rectangle that has to come out full, so the
     furniture declares its inches and `look.budgets` hands the plates exactly
     what is left. The words of a section are gathered onto their own sheet and
     its frames onto theirs, because mixing them packs badly.
  2  **One width, forever.** Everything is in points and inches. Nothing here
     is fluid, and nothing should be.
  3  **A sheet is entered cold.** So every sheet repeats where it is — a
     running mark at the same height, a number at the foot — and every title
     starts at the same eyeline, so no two sheets read as two documents.
  4  **Its own ground.** A PDF carries its paper; the field is painted here.
  6  **A cover**, because a PDF is emailed and opened months later with nothing
     around it to say what it is.
  7  **Embedded faces**, loaded from the deck's own `assets/fonts`.
  8  **Given the rows, solving the size** — `render.py` does that part; this
     file only has to give it a `.shots` box of an honest height.

Rule 5 has no counterpart here at all: nothing else is in the room.

**Written once.** `bible.py` calls this only when a folder has no
`template.html`. After that the design is his and nothing regenerates it.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import look as look_mod  # noqa: E402

#: Kept so `bible.py --from <deck>` still resolves, and so anything that used to
#: import it does not break. Nothing in this file reads it any more.
TITH = (Path.home() / "Library/CloudStorage/GoogleDrive-you@example.com"
        / "My Drive/cinematography/portfolio/outbound/decks/pitch-deck/template.html")


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def stylesheet(theme):
    """The sheet, its furniture, and the boxes `render.py` fills.

    Every class `render.py` emits is defined here — `.page`, `.phead`,
    `.ptitle`, `.pcred`, `.pcont`, `.shots`, `.rw`, `.pnote`, `.foot`, `.r`,
    `.mosaic`. A design that omits one of them prints that part as unstyled
    text, which is how the first attempt at this file came out looking like a
    wiki page.
    """
    lk = look_mod.look_of(theme)
    w, h, css_size = look_mod.page_of(theme)
    s = lk["sizes"]
    return f"""<style>
{look_mod.font_faces(lk)}
@page{{size:{css_size};margin:0}}
*{{margin:0;padding:0;box-sizing:border-box;
   -webkit-print-color-adjust:exact;print-color-adjust:exact}}

/* The film's look, and the only place it is named. Everything below is the
   medium. Change these in theme.json, not here — web.html reads the same
   values, and the two are meant to agree about colour. */
:root{{
  --ground:{lk["ground"]};
  --ink:{lk["ink"]};
  --accent:{lk["accent"]};
  --muted:{lk["muted"]};
  --rule:{lk["rule"]};
  --title:{s["title"]}pt;
  --claim:{s["claim"]}pt;
  --note:{s["note"]}pt;
  --label:{s["label"]}pt;
  --mark:{s["mark"]}pt;
  --eye:{lk["eye_in"]}in;      /* rule 3: where a title starts, every sheet */
  --pad:{lk["pad_in"]}in;
  --foot:{lk["foot_in"]}in;
  --plate:{lk["plate_in"]}in;  /* rule 8: a gap between frames is a physical margin */
}}

/* ---------- the sheet (rules 1 and 4) ---------- */
/* The page paints its own ground because nothing exists around it, and it is a
   fixed rectangle: `overflow:hidden` so a mistake shows as a crop rather than
   as a silently longer document. */
html,body{{background:var(--ground)}}
body{{font-family:TX,{lk["text"]["fallback"]};color:var(--ink);
     font-size:var(--note);line-height:1.5}}
.page{{width:{w}in;height:{h}in;position:relative;overflow:hidden;
      background:var(--ground);page-break-after:always;
      padding:var(--eye) var(--pad) var(--foot)}}
.page:last-child{{page-break-after:auto}}
img{{display:block;width:100%;height:auto}}

/* ---------- where you are (rule 3) ---------- */
/* A printed page gets picked up cold, so every sheet says for itself which
   section it is and how far in. Both are pinned, not in the flow, so the
   eyeline below is the same on a sheet of words and a sheet of frames. */
.mark,.phead{{position:absolute;top:var(--pad);left:var(--pad);right:var(--pad);
      font-family:TX,{lk["text"]["fallback"]};font-size:var(--mark);
      letter-spacing:.26em;text-transform:uppercase;color:var(--muted)}}
.phead.cont .pcont span{{font-style:italic;letter-spacing:.06em;
      text-transform:none}}
/* `render.py` writes this size inline — 46pt, sized to the length of the
   title — because in a portfolio deck the plate page's head *is* the work's
   name. In a bible the section already had its own sheet, so what belongs here
   is the running mark, at the one size that role has everywhere else. An inline
   style is the only thing `!important` can answer. */
.ptitle{{font-size:var(--mark) !important;letter-spacing:.26em}}
.pcred{{display:none}}   /* a bible has no per-plate credit; a portfolio deck does */
.foot{{position:absolute;left:var(--pad);right:var(--pad);bottom:calc(var(--foot) / 2);
      display:flex;justify-content:space-between;align-items:baseline;
      font-family:TX,{lk["text"]["fallback"]};font-size:var(--mark);
      letter-spacing:.22em;text-transform:uppercase;color:var(--muted)}}

/* ---------- one size per role (rules 2 and 3) ---------- */
/* Absolute, because the sheet is one width forever — and fixed, because in
   print a size change invalidates every page budget after it. */
.head{{font-family:DP,{lk["display"]["fallback"]};font-weight:400;
      font-size:var(--title);line-height:1.04;color:var(--accent)}}
.lead{{font-family:DP,{lk["display"]["fallback"]};font-size:var(--claim);
      line-height:1.38;margin-top:.20in;max-width:5.9in}}
.note{{font-size:var(--note);line-height:1.55;margin-top:.22in;max-width:5.9in}}
.note + .note{{margin-top:.12in}}
.sub{{font-size:var(--label);letter-spacing:.22em;text-transform:uppercase;
     color:var(--muted);margin-top:.28in}}
.rule{{height:1px;background:var(--rule);margin:.22in 0 0;max-width:5.9in}}
ul{{margin:.22in 0 0 .22in;max-width:5.9in}}
li{{font-size:var(--note);line-height:1.55;margin-top:.08in}}
em,i{{font-style:italic}}

/* ---------- the frames (rule 8) ---------- */
/* `render.py` is handed the rows and solves the size: it writes each row's
   height in inches and, where a group asked for one shape, equal columns. All
   this has to do is not fight it. `object-fit:cover` is what makes the trim
   at the sides real — a page that comes out a little short is widened and the
   edges taken, which is print's answer to a rectangle that must come out full. */
.shots{{display:flex;flex-direction:column;gap:var(--plate);
       justify-content:flex-start;overflow:hidden}}
/* **The row's single track is the row's own height, and that is load-bearing.**
   Without `grid-auto-rows`, the implicit track is `auto` and sizes itself to
   the pictures; `height:100%` on an image inside an auto track is circular and
   resolves to the image's natural height, so every row quietly grew past the
   inches `render.py` measured for it and the page ran long. The explicit track
   is what makes the inline height mean something. */
.rw{{display:grid;gap:var(--plate);grid-auto-rows:100%;margin:0 auto;width:100%}}
.rw img{{width:100%;height:100%;min-width:0;min-height:0;object-fit:cover}}
.mosaic{{display:flex;flex-direction:column;gap:var(--plate)}}
.pnote{{font-size:var(--label);color:var(--muted);margin-top:.16in;max-width:5.9in}}

/* ---------- the cover (rule 6) ---------- */
/* A PDF travels alone and is opened months later with nothing around it, so it
   has to say whose it is. The only sheet that is centred, and meant to be. */
.page.cover{{display:flex;flex-direction:column;align-items:center;
      justify-content:center;text-align:center;padding:var(--pad)}}
.cover .film{{font-family:DP,{lk["display"]["fallback"]};font-size:var(--title);
      line-height:1.05;color:var(--accent)}}
.cover .what{{font-size:var(--label);letter-spacing:.30em;text-transform:uppercase;
      color:var(--muted);margin-top:.26in}}
.cover .by{{font-size:var(--label);letter-spacing:.18em;color:var(--muted);
      margin-top:1.1in}}
</style>
"""


def cover(film):
    """Rule 6, and the one sheet allowed to be centred."""
    return f"""<!--SECTION:cover-->
<div class="page cover">
  <div class="film" data-t="cover.title1">{esc(film)}</div>
  <div class="what" data-t="cover.sub1">Visual Language</div>
  <div class="by" data-t="cover.by1">Nathaniel Regier, Cinematographer</div>
</div>
"""


def words_page(film, sec, counts):
    """A section's writing, on its own sheet.

    **Gathered, not mixed** — rule 1. On a sheet that has to come out full,
    words and frames pack badly together, so the argument gets its own page and
    the frames get theirs. (The other way is available: a `<!--HEAD:<slug>:<in>-->`
    block is lifted by `render.py` and printed above the group's first plate
    page, with its inches taken off that page's budget. It is the right move for
    a section with two lines and four pictures, and it wants its height measured
    rather than guessed, so the scaffold does not reach for it.)
    """
    sid, name = sec["id"], sec["name"]
    out = [f"<!--SECTION:{sid}-->", '<div class="page">',
           f'  <div class="mark">{esc(film)}</div>',
           f'  <div class="head" data-t="{sid}.head1">{esc(name)}</div>',
           '  <div class="rule"></div>']
    if counts.get("p"):
        out.append(f'  <p class="lead" data-t="{sid}.p1"></p>')
        for i in range(2, counts["p"] + 1):
            out.append(f'  <p class="note" data-t="{sid}.p{i}"></p>')
    for i in range(1, counts.get("q", 0) + 1):
        out.append(f'  <p class="lead" data-t="{sid}.q{i}"></p>')
    if counts.get("b"):
        out.append("  <ul>")
        for i in range(1, counts["b"] + 1):
            out.append(f'    <li data-t="{sid}.b{i}"></li>')
        out.append("  </ul>")
    for i in range(1, counts.get("sub", 0) + 1):
        out.append(f'  <div class="sub" data-t="{sid}.sub{i}"></div>')
    out += [f'  <div class="foot"><span>{esc(name)}</span>'
            '<span class="r">00</span></div>', "</div>", ""]
    return "\n".join(out)


def template_for(film, sections, theme=None, logo=True):
    """The print design for a new bible: the medium, and the film's look.

    `theme` is the deck's own `theme.json`, already written — it carries the
    palette, the faces and the page size, and `web_design.py` is handed the
    same one. `logo` is kept for callers that still pass it.
    """
    theme = theme or {}
    body = [cover(film)]
    for sec in sections:
        # **A dict of zeros is still a dict.** `if sec.get("counts")` was true
        # for a section with no prose at all, and printed a sheet holding one
        # heading and half an inch of nothing.
        if any((sec.get("counts") or {}).values()):
            body.append(words_page(film, sec, sec["counts"]))
        if sec.get("pictures"):
            # Filled by `render.py`, placed exactly where this section's words
            # end, which is the whole reason the marker exists.
            body.append(f"<!--SECTION:__p_{sec['id']}__-->\n")
    head = (f'<!DOCTYPE html>\n<html><head><meta charset="utf-8">'
            f'<title>{esc(film)} — Visual Language</title>\n'
            f'{stylesheet(theme)}</head>\n<body>\n')
    return head + "".join(body) + "</body></html>\n"
