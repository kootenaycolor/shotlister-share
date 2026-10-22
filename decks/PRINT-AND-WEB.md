# A sheet and a screen are different documents

His correction, 2026-09-08, and it is the whole point of this file:

> *"The goal here is not to start from the Call Her Back design, but from the
> underlying differences between how one would design a PDF for any film
> (regardless of the content or the style of that film) versus HTML."*

So nothing below names a colour, a typeface, a rail, a rainbow or a film. Those
are a project's own and belong in its `theme.json` and its two design files. What
is written here is the part that would be true of **any** deck in **any** style:
the eight things the medium decides for you before a designer arrives.

A deck has two design files on purpose — `template.html` for the press,
`web.html` for the portal — and they are edited separately. This is the list of
what they are separate *about*. If a difference between a deck's two files is not
one of these eight, it is probably drift, and one of the two is wrong.

---

## 1. The container

**Print has many containers of a fixed size. The web has one of unbounded
length.**

This is the difference the other seven lean on. A sheet is 8.5 by 11 inches
whether or not the writing fills it, so print **packs**: content is cut into
page-sized units, every unit's leftover space has to be resolved by somebody,
and a block that will not fit has to move, shrink or split. That is why a print
design ends up doing arithmetic — heights declared in inches, budgets, rows
counted to fill a plate — and why changing one type size invalidates every page
after it.

The web has no leftover space, because there is no bottom edge to reach. Content
is **ordered**, not packed. Nothing needs a height, nothing needs a budget, and
adding a paragraph costs nothing downstream.

The consequence people miss: this changes *the order of the content itself*, not
only its styling. Packing pushes a design toward gathering — all the writing on
its own sheets, then all the pictures on theirs — because mixed content packs
badly. Ordering pushes the other way, toward alternating small blocks, because a
reader who scrolls past a screen of unbroken pictures has lost the thread. **The
two files are allowed to disagree about how finely the sections are cut.** They
are not allowed to disagree about what the sections say.

## 2. The width

**Print has one width, forever. The web has every width.**

A sheet is one measure and one reading distance, so a print design may size
anything to the page and be right about it permanently. A web design cannot size
anything to a width it does not know, and every block has to survive being 390
pixels wide on a phone in a car.

So: absolute measurements are correct in print and a bug on the web; fluid ones
are correct on the web and pointless in print. A layout of columns is a
commitment in print and a suggestion on the web. Anything drawn side by side on
a sheet needs an answer for what happens when it cannot be.

## 3. Where the reader is

**A printed page is entered cold. A web page is entered in sequence.**

Somebody picks up a printed deck at sheet 34 — flipping, or because that is the
sheet that was left on the table. That sheet has to say for itself where it is:
what section this is, and how far in. So print **repeats** — a running head, a
page number, the section's name again at the top of every sheet.

A screen is continuous. Nobody arrives at the middle without passing the start,
and the browser already draws how far through the document they are. So the web
**persists** instead of repeating: the name of the section can stay in view
while its content moves past, which is impossible on paper, and does the same
job with none of the repetition.

Print addresses itself by page number and needs a contents. The web addresses
itself by link and needs anchors.

## 4. The ground

**A PDF carries its own paper. A web page lands on somebody else's.**

Nothing exists around a PDF, so its background is part of it and is free — a
design may be black, cream or oxblood and it costs only ink.

A deck on the portal is drawn inside a page that already has a ground, a header
and a stylesheet. A slab of the deck's own colour dropped into that reads as a
PDF pasted onto a website, which is the specific thing he has objected to twice.
So a web design **inherits the ground** and keeps its own colour for the parts
that are actually the identity — the type, the rules, the accents.

## 5. Somebody else's stylesheet

**Only the web has this problem, and it has it every time.**

A PDF is rendered alone. A deck page is rendered inside the portal, so
`hub.css` and `front.css` are already in force, and any plain word both files
name — `frames`, `body`, `rail`, `row` — collides. The two selectors weigh the
same and only the properties the deck happens to mention get won; everything it
never thought to mention arrives from the front of house.

So a web design has two obligations a print design has none of: **scope
everything** under one wrapper class, and **give the shared words back their
plain meaning** at the top of the file before the design speaks. Renaming is the
better fix where a word is load-bearing on both sides.

## 6. Front matter

**A PDF travels alone and must introduce itself. A web page arrives introduced.**

A PDF is sent, downloaded, opened months later with no context around it, so it
opens with a cover: whose it is, what film, what document. That cover is doing
real work.

A page on the portal is reached through the film it belongs to, under the site's
own header, with the film's name already on screen. A full-height cover there is
a screen the reader scrolls past to reach the document. So the web opens with a
title and starts.

## 7. Fonts and pictures

**Print embeds. The web fetches.**

A print file loads its typefaces from the folder beside it and places pictures
at a physical size, where resolution is the constraint and nothing can fail to
arrive. It is rendered once, on a Mac, by somebody who is watching.

A web file's typefaces and pictures are fetched over a connection that may be a
phone's. Every face needs a real fallback stack, every picture needs to be worth
its download, and the page has to look correct before either has landed.

## 8. A grid of pictures is solved from opposite ends

Both media lay pictures out in rows, and neither wants to crop to do it. That is
where the agreement stops.

**In print the rows are given and the size is solved.** A sheet is a fixed
rectangle that has to come out full, so which pictures share a row is whatever
was arranged, and the free variable is scale: the block is narrowed until it
fits, or widened a little and trimmed at the sides until it lands exactly, and a
group with too little in it is left short rather than blown up. Leftover space
on a sheet is a defect somebody has to resolve.

**On the web the size is given and the rows are solved.** The column has a width
and no bottom, so scale is not free — the width is the width — and the free
variable is *which pictures share a row*. A row's height is the column width
divided by the shapes in it, so the only way to stop a row being too tall is to
put more pictures in it. The layout is re-packed, not re-scaled, and "full" only
ever means reaching the right-hand edge.

Three consequences, each of which has already cost a rebuild:

- **The rows may not be shared between the two files.** Same pictures, same
  order, different rows. Reusing the print rows on the web was a real bug, and
  carrying web rows back to paper would be the same bug facing the other way.
- **A row of one means opposite things.** On paper a lone picture is a plate —
  the strongest emphasis a page can make. In a column it is one picture at full
  width, which for anything squarer than a wide crop is most of a phone screen
  tall. Print's emphasis gesture is the web's failure mode, so a web design has
  to say *this one matters* some other way.
- **Tall is free on paper and expensive on screen.** A sheet is portrait and a
  tall picture costs nothing. On the web it costs scrolling, so a web design
  needs a ceiling on row height that a print design has no use for.

And the units follow the medium: a gap between pictures is a physical margin in
print and belongs in inches; on the web it is relative and has to hold at every
width.

**What is *not* a medium difference:** whether a group is drawn as its pictures'
true shapes or as a contact sheet of identical cells. That is a choice about
that group, and both sides owe it. For a long time only the web paid: the press
read `deck.json`, which holds rows and no ratios, and never opened the
arrangement at all — so the same group came out a tidy grid on the portal and
ragged on paper. Fixed 2026-09-08 (`grid_ratios` in `render.py`), and it is
worth keeping as the worked example of the test below: a difference that
answers none of the eight is not a difference, it is a bug.

---

## What this leaves to the film

Everything else. The palette, the typefaces, the weight and tracking, whether
there is a progress mark at all and what it looks like, the shape of a heading,
the concept behind when a page changes colour. Those are the design, they are
his, and no rule here touches them.

**The test.** Take a difference between a deck's two files and ask which of the
eight it is an answer to. If it is not an answer to any of them, the same choice
should have been made in both files, and one of them is wrong.

**What runs it, and what does not.** The half of the test a program can do is
rule 1's last line — the two may be cut differently, never say different things
— and `decks/tools/twin.py <deck-folder>` does it: same words on both sides, a
word in `text.md` for each, `cover.` allowed to be print-only. `render.py` says
it after a print without ever refusing to print. The other seven are a designer's
to keep, which is why they are written down rather than enforced.

**Where the two designs come from.** A new bible is scaffolded by
`bible_design.py` (the press) and `web_design.py` (the portal); each holds its
own half of the eight and no colour, typeface or size of its own. Those come
from the film's `theme.json` through `look.py`, which both read — so a deck
cannot start life with its two designs already disagreeing about what colour
anything is.
