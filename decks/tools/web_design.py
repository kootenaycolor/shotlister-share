#!/usr/bin/env python3
"""The web half of a deck's design — a document somebody scrolls.

His rule, 2026-09-05: *"The website should show the same overall styling but not
format, it's a different medium so we treat it differently but it should feel in
the same world as the PDF."* And his correction of 2026-09-08, which is what
this file is now written against:

> *"The goal here is not to start from the Call Her Back design, but from the
> underlying differences between how one would design a PDF for any film
> (regardless of the content or the style of that film) versus HTML."*

So this is not the print template with the page breaks taken out, and it is not
a copy of any film's look either. The look — colours, faces, sizes — comes from
the film's `theme.json` through `look.py`, which the print scaffold reads too,
so the two cannot start life disagreeing about what colour anything is. What is
written *here* is the part of a scrolled document that is true whatever it looks
like. Every piece of it is one of the eight in `decks/PRINT-AND-WEB.md`:

  1  **One roll, not pages.** No page arithmetic, no inch budgets, no row
     packing. And the sections are cut differently on purpose: a short block of
     writing before *each* group of frames, because a screen of unbroken
     pictures loses the thread. The words must match the print design; the
     cutting need not, and `twin.py` checks exactly that line.
  2  **Every width.** Type is fluid and capped, the measure is a column rather
     than a sheet, and anything side by side has an answer for being narrow.
  3  **Entered in sequence.** So the section's name *persists* beside the
     writing instead of being repeated at the top of every screen, and the
     document is addressed by link — anchors and a jump bar — not by number.
  4  **No ground of its own.** A deck is drawn inside the portal's page, which
     already has a background. A slab of the film's colour here reads as a PDF
     pasted onto a website. The colour lives in the type and the rules.
  5  **Somebody else's stylesheet.** Everything is scoped under `.deckweb`, and
     the words the portal also uses are handed back their plain meaning first.
     This one has no counterpart in print at all.
  6  **No cover.** The page is reached through the film and arrives named, so a
     full-height cover is a screen to scroll past. A masthead, and start.
  7  **Fetched, not embedded.** Web faces with a real fallback stack, because
     the download can fail and the page has to be right before it lands.
  8  **Given the size, solving the rows.** `publish.py` re-packs the frames for
     a column and writes each row's shape inline; all this does is not fight it,
     and cap what a row may become on a phone.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import look as look_mod  # noqa: E402


def esc(t):
    return (str(t).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def font_link(lk):
    """Rule 7. The faces are fetched, so they are asked for by name and every
    one of them is written with a fallback that is already on the machine."""
    want = []
    for face in (lk["display"], lk["text"]):
        name = (face.get("web") or "").strip()
        if name:
            want.append("family=" + name.replace(" ", "+") +
                        ":ital,wght@0,400..900;1,400..900")
    if not want:
        return ""
    return ("@import url('https://fonts.googleapis.com/css2?"
            + "&".join(want) + "&display=swap');")


def stylesheet(theme):
    lk = look_mod.look_of(theme)
    s = lk["sizes"]
    dp = f"'{lk['display']['web']}', {lk['display']['fallback']}"
    tx = f"'{lk['text']['web']}', {lk['text']['fallback']}"
    # Print's point sizes are the *top* of a fluid scale here, never a fixed
    # value — rule 2. A sheet is one width forever and a screen is not.
    return f"""{font_link(lk)}
/* ---------- the film's look, and the only place it is named ---------- */
/* `ground` is deliberately absent: rule 4, the portal's page already has one. */
.deckweb{{--ink:{lk["ink"]};--accent:{lk["accent"]};--muted:{lk["muted"]};
         --rule:{lk["rule"]};
         --gap:10px;--rest:clamp(44px,6vw,88px);
         color:var(--ink);font-family:{tx};
         font-size:clamp(15px,1.05vw,{s["note"] * 1.6:.0f}px);line-height:1.62;
         -webkit-font-smoothing:antialiased}}
.deckweb *{{box-sizing:border-box}}

/* ---------- the portal's own words, handed back (rule 5) ---------- */
/* A deck is drawn *inside* the portal's page, so `hub.css` and `front.css` are
   already in force. Where they name a word this design also uses, the two
   selectors weigh the same and only the properties this file happens to
   mention are won — everything it never thought to mention arrives from the
   front of house. Measured on his bible, 2026-09-08: `.frames` was a flex
   strip with a grey ground and a border, so every block of photographs was laid
   out sideways and boxed; `.frow` was a filter button, so every row arrived
   with padding, a rounded corner and 44px of minimum height on a phone;
   `.body` was `display:flex`, so the writing was a row.
   The portal's `.rail` is answered by renaming instead: this design calls its
   own `srail`. **A new design in this folder wants this block copied into it.** */
.deckweb .body{{display:block;flex:initial;min-height:auto}}
.deckweb .frames{{gap:0;width:auto;position:static;
                 background:none;border:0;border-radius:0;overflow:visible}}
.deckweb .frames .frow{{padding:0;background:none;border-radius:0;min-height:0;
                       text-align:left;cursor:auto;font-size:inherit;color:inherit}}
.deckweb .frames .frow:hover{{background:none}}
.deckweb .sub{{margin:0;font-size:inherit;color:inherit}}

.deckweb .inner{{max-width:1040px;margin:0 auto;padding:0 24px}}

/* ---------- the masthead (rule 6) ---------- */
/* Not a cover. The film's name is already above this on the portal, so the
   document says what it is and starts. */
.deckweb .top{{padding:clamp(40px,7vw,86px) 0 clamp(20px,3vw,34px)}}
.deckweb .top h1{{font-family:{dp};font-weight:400;
                 font-size:clamp(30px,5.2vw,{s["title"] * 1.5:.0f}px);
                 line-height:1.04;margin:0;color:var(--accent)}}
.deckweb .top .kick{{font-size:11px;letter-spacing:.30em;text-transform:uppercase;
                    color:var(--muted);margin:14px 0 0}}

/* ---------- the jump bar (rule 3) ---------- */
/* A scrolled document is addressed by link, where a printed one is addressed by
   page number. Plain anchors, no script. It wraps rather than scrolling, so it
   still reads at 390px. */
.deckweb .tabs{{display:flex;flex-wrap:wrap;gap:6px 18px;
               padding:14px 0 0;border-top:1px solid var(--rule)}}
.deckweb .tabs a{{font-size:11px;letter-spacing:.16em;text-transform:uppercase;
                 color:var(--muted);text-decoration:none}}
.deckweb .tabs a:hover{{color:var(--accent)}}

/* ---------- the section: a name that stays, and a column (rules 2 and 3) ---------- */
/* On paper the section's name is reprinted at the top of every sheet because a
   sheet is entered cold. Here it is entered in sequence, so the name persists
   beside the writing instead — and on a narrow screen there is no beside, so it
   becomes an ordinary heading above it. */
.deckweb .sec{{display:grid;grid-template-columns:minmax(140px,200px) 1fr;
              gap:clamp(18px,3vw,40px);margin:var(--rest) 0}}
.deckweb .srail{{position:sticky;top:18px;align-self:start}}
.deckweb .srail .label{{font-size:10px;letter-spacing:.28em;text-transform:uppercase;
                       color:var(--muted);margin:0 0 8px}}
.deckweb .srail h2{{font-family:{dp};font-weight:400;
                   font-size:clamp(19px,2.2vw,{s["title"] * 0.62:.0f}px);
                   line-height:1.12;margin:0;color:var(--accent)}}

/* ---------- the writing ---------- */
.deckweb .body .lead{{font-family:{dp};
                     font-size:clamp(17px,1.6vw,{s["claim"] * 1.7:.0f}px);
                     line-height:1.45;margin:0}}
.deckweb .body p{{margin:0 0 .85em;max-width:64ch}}
.deckweb .body p:last-child{{margin-bottom:0}}
.deckweb .body ul{{margin:.9em 0 0;padding-left:1.1em;max-width:64ch}}
.deckweb .body li{{margin:.4em 0}}
.deckweb .body h3{{font-size:11px;letter-spacing:.24em;text-transform:uppercase;
                  color:var(--muted);font-weight:400;margin:1.4em 0 .5em}}
.deckweb .body em,.deckweb .body i{{font-style:italic}}

/* ---------- the frames (rule 8) ---------- */
/* `publish.py` is given the width and solves the rows: it decides which frames
   share a line so no line is too tall, and writes each row's shape and each
   figure's width inline. Nothing here may contradict that — the only job left
   is the gap, and what happens when the column is a phone. */
.deckweb .frames{{display:flex;flex-direction:column;gap:var(--gap);
                 margin:calc(var(--rest) * .5) 0}}
.deckweb .frow{{display:flex;gap:var(--gap);width:100%;align-items:stretch}}
.deckweb .frames figure{{margin:0;overflow:hidden;min-width:0}}
.deckweb .frames figure img{{display:block;width:100%;height:100%;
                            object-fit:cover}}
/* A lone frame is a plate on paper and the worst thing on a screen — rule 8.
   It is held back to the measure of the writing rather than run full width. */
.deckweb .frow.solo{{max-width:min(100%,720px)}}

/* Rule 2, and the only place `!important` is right in this file: the row's
   shape is written inline by `publish.py`, and a phone has to be able to
   overrule it. Four frames across a 390px screen is four thumbnails. */
@media (max-width:640px){{
  .deckweb .sec{{grid-template-columns:1fr}}
  .deckweb .srail{{position:static}}
  .deckweb .frow{{display:grid !important;
                 grid-template-columns:repeat(2,minmax(0,1fr)) !important;
                 aspect-ratio:auto !important}}
  .deckweb .frow figure{{width:auto !important}}
  .deckweb .frow.solo{{grid-template-columns:1fr !important}}
}}

/* ---------- the foot ---------- */
.deckweb .foot{{margin:var(--rest) 0 clamp(30px,5vw,70px);
               padding-top:14px;border-top:1px solid var(--rule);
               font-size:11px;letter-spacing:.18em;text-transform:uppercase;
               color:var(--muted)}}
"""


def words_block(sec, film, counts):
    """One section: its name in the rail, its writing in the column.

    **The keys match the print design exactly** — `sid.p1`, `sid.b2` — so one
    `text.md` feeds both and editing the copy changes the website and the PDF
    together. That is the whole of what "the two say the same thing" means
    mechanically, and `twin.py` is what notices when it stops being true.
    """
    sid, name = sec["id"], sec["name"]
    out = [f'  <div class="sec" id="s-{sid}">',
           '    <div class="srail">',
           f'      <p class="label">{esc(film)}</p>',
           f'      <h2 data-t="{sid}.head1">{esc(name)}</h2>',
           '    </div>',
           '    <div class="body">']
    if counts.get("p"):
        out.append(f'      <p class="lead" data-t="{sid}.p1"></p>')
        for i in range(2, counts["p"] + 1):
            out.append(f'      <p data-t="{sid}.p{i}"></p>')
    for i in range(1, counts.get("q", 0) + 1):
        out.append(f'      <p class="lead" data-t="{sid}.q{i}"></p>')
    if counts.get("b"):
        out.append("      <ul>")
        for i in range(1, counts["b"] + 1):
            out.append(f'        <li data-t="{sid}.b{i}"></li>')
        out.append("      </ul>")
    for i in range(1, counts.get("sub", 0) + 1):
        out.append(f'      <h3 data-t="{sid}.sub{i}"></h3>')
    out += ["    </div>", "  </div>", ""]
    return "\n".join(out)


def template_for(film, sections, theme=None):
    """The web design for a new bible: the medium, and the film's look.

    **No cover, and that is rule 6.** The print scaffold opens with one because
    a PDF travels alone; this opens with a masthead because the portal has
    already said whose film this is.
    """
    theme = theme or {}
    named = esc(film)
    jump = "".join(f'<a href="#s-{s["id"]}">{esc(s["name"])}</a>'
                   for s in sections if any((s.get("counts") or {}).values()))
    body = []
    for sec in sections:
        body.append(f"<!--SECTION:{sec['id']}-->\n")
        if any((sec.get("counts") or {}).values()):
            body.append(words_block(sec, film, sec["counts"]))
        if sec.get("pictures"):
            body.append(f"<!--SECTION:__p_{sec['id']}__-->\n")
    return f"""<style>
{stylesheet(theme)}</style>
<div class="deckweb alone"><div class="inner">
  <header class="top">
    <h1>{named}</h1>
    <p class="kick">Visual Language</p>
  </header>
  <nav class="tabs">{jump}</nav>
{"".join(body)}  <div class="foot">{named} &nbsp;·&nbsp; Nathaniel Regier</div>
</div></div>
"""
