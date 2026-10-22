# Decks

**Folded into Shotlister on 2026-09-06**, from its own repo at
`~/Developer/deck-builder`. What pinned it there was the old editor's absolute
paths, and the editor is gone — it is a page of the portal now
(`hub/src/editor.js`, `hub/public/deck.js`). What lives here is **the press and
the deck tools**: making the PDF, pushing a deck's record to its film, and
scaffolding a deck out of a Notion page.

The hub is a sibling in this tree rather than an address, which is why one
expired Cloudflare login can no longer take down two programs at once.

**A deck has two designs, and `PRINT-AND-WEB.md` is what they are separate
about** — the eight things the medium decides before a designer arrives. Read it
before writing or changing either design file. The parts that carry it:

| | |
| --- | --- |
| `tools/bible_design.py` | the print design a new bible starts with — pages, one eyeline, a cover |
| `tools/web_design.py` | the web design — a column, a name that stays, the portal's ground |
| `tools/look.py` | the film's own look, read by both, out of its `theme.json` |
| `tools/twin.py` | do the two still say the same thing? `python3 twin.py <deck-folder>` |

One press, many decks. The tool lives here; a deck lives wherever it belongs
— usually inside its project's folder in Drive, sometimes under
`portfolio/outbound/decks/` if it is not tied to one project.

`Deck Editor.app` is a native macOS app (`mac/`, SwiftUI, Liquid Glass). It
lists every deck you have opened before down the left, and shows the editor in
its own window instead of a browser tab. The list is kept in
`~/Library/Application Support/deck-builder/decks.json`; opening a deck adds it,
and entries whose folder has moved or gone are dropped automatically.

## The app

`Deck Editor.app` is a window on the portal. **The editor itself is no longer
here** — his rebuild of 2026-09-05 moved it to `your-domain.example`, where a
deck is a page of a film, so a deck has one home instead of a folder in Drive
and a copy on the website that drift apart. Notion AI can reach it there; it
never could here.

```
mac/
  Sources/DeckEditorApp.swift   the whole app: a window, a web view, three menus
  Info.plist, build.sh, make-icon.sh, AppIcon.icns
```

Rebuild it with `mac/build.sh`. **It needs no permission of any kind** — it
reads no folder, starts no process and opens no Terminal. That is what keeps a
rebuild cheap, since macOS ties permissions to an app's exact signature and
every rebuild is a new app as far as the system is concerned. Keep it that way.

The signed-in session is kept between launches, so signing in to the portal
happens once. A link that leaves the portal opens in his own browser rather than
stranding him in a window with no address bar.

### What went, and why it is not missed

The editor was a Python server on a fixed port, started through a **Terminal
window** because macOS will not let an ad-hoc signed app read Google Drive. The
deck lived in Drive beside it. Three faults came straight out of that shape and
are gone with it: a stale server on the fixed port answering in place of the new
one; the preview pointing at pictures on his Mac while the published page
pointed at different ones; and the folder in Drive drifting from the website.

`tools/editor.py`, `tools/agent.command`, `tools/launch.sh`,
`tools/open-deck.command` and `legacy/` were deleted on 2026-09-05.

**What is still a Mac's job is the press.** Making a beautiful PDF wants his
real typefaces and a real browser, and a worker has neither — so `render.py`
stays, and `Rebuild PDF.app` sits beside each deck.

## The press runs itself

`agent.sh install` puts a launchd agent behind the press. Every three minutes it
asks the portal whether any deck has changed, and when one has it pulls the
change down, prints it, and files the PDF under the film's Documents — without
him pressing anything. `agent.sh log` says what it has done; `agent.sh once`
runs a single pass by hand; `agent.sh remove` turns it off.

**The catch, plainly:** the Mac has to be on. A deck changed while it is shut
prints when it next wakes.

**Two folders may not claim one deck.** They did, on 2026-09-06: a scratch copy
left in the registry by an earlier session named the same film and page as his
real bible, so a test deck printed first and put a 0.2 MB PDF over the film's
Visual Bible. A key claimed twice is now printed from neither and said out loud,
because which of two folders is his is not something a script can know.

## Where a project's decks live (since 2026-10-15)

```
projects/<slug>/1-creative/decks/<deck-name>/
  <name>_<date>.pdf     current finished PDF
  z-archive/            older dated PDFs
  z-source/             all working files (the folder below), launcher apps, build
```

The deck's registered folder is its `z-source`. Web-only pages (camera-tests,
look-board, dump-board) use the same layout with no PDF. General decks stay under
`portfolio/outbound/decks/`. `render.py` files the PDF at the top and archives the
older ones; `new_deck.py --project <slug>` and `bible.py <.../z-source>` scaffold it.

## A deck folder

```
decks/<name>/
  theme.json      page size, grid budgets, palette, per-project notes
  sources.json    where images come from, and their titles and credits
  template.html   the design. <!--SECTION:id--> markers, data-t text keys
  text.md         every word in the deck, keyed to those data-t attributes
  deck.json       what you chose and arranged        ← written by the editor
  assets/         fonts, logo, images the template refers to directly
  build/          render output
  Edit Deck.app   opens the editor on this folder
  Rebuild PDF.app renders it
```

`deck.json` is the only file the editor writes. The stills in the deck *are*
the stills in the pages, so there is no second list to fall out of step.

## A visual bible is not a deck

`tools/bible.py` is the other half of this program, and it works the opposite
way round.

A deck is an **arrangement** — chosen projects, chosen stills, packed into rows
on numbered pages, against a template whose sections are named in advance
(`howiwork.lede1`). You arrange it here and it goes out as a PDF.

A visual bible is a **sequence** — whatever headings, prose, lists and picture
rows exist, in the order they were written — and it is authored somewhere else
entirely. His decision, 2026-09-04: **the film's page on the portal is the
source of truth for a bible.** `your-domain.example` draws it directly, and
anything that can reach `mcp.your-domain.example` can write it: Notion AI,
Claude, the Mac app. This is the printer.

```bash
python3 tools/bible.py <folder> --film "Call Her Back"
```

That makes the folder if it is not there, pulls the page and its pictures out
of the bucket, prints a PDF beside them, and leaves a **Rebuild Bible.app** to
double-click. Afterwards the folder holds:

```
visual-bible/
  bible.json      which film, which page, and how it should print
  template.html   the design — yours, and never regenerated once it exists
  page.json       what the portal said, last time it was asked
  img/            the pictures, pulled down
  build/          working files
  Rebuild Bible.app
```

### Two outputs, one design

His rule, 2026-09-05: *"The website should show the same overall styling but not
format, it's a different medium so we treat it differently but it should feel in
the same world as the PDF."*

So a deck carries two templates over one set of content:

| | |
| --- | --- |
| `template.html` | the sheet. Pages, inch budgets, packed rows. `render.py` prints it |
| `web.html` | the page. A flow that reflows. `publish.py` builds it |

Both read the same `deck.json` and the same `text.md`, with the same `data-t`
keys — so a word changed or a picture reordered in Deck Editor moves both.

**What crosses between them is the identity, not the substrate.** The typeface,
the accent, the `->` before a section name, the rule beneath it, the measure of
a paragraph, the rhythm. **Not the paper.** His note the same day: *"i probably
wouldnt want to change the entire background of the web page because that would
feel not very integrated"* — and he is right, a cream slab dropped into the dark
portal reads as a PDF pasted onto a website. The web page takes the portal's own
ground and its own tokens; only the accent's *hue* is carried over, with its
lightness raised so his `#2136C8` stays legible on near-black.

### The shelf

The drawer along the foot of the editor is the film's library, and it is
where stills come from. Four tabs: *This Deck*, *Film*, *Unused* — what is on
the film and not yet in this deck, the tab a deck is built from — and *Notion*,
what the press last pulled. *Add Stills…* is a real file picker (in the app it
is the Mac's own open panel); dropping files on the window does the same. The
grid button wraps the strip into rows. Shift picks a run and ⌘ adds one, and
the whole pick drags in as one row; a second press on a still opens it whole
with its size. Every still goes to the *film*, by its own contents, so the same
picture twice makes one copy and every deck of the film can reach it.

### Two views, and the other channel

Deck Editor shows a deck **two ways**, switched in the toolbar:

| | |
| --- | --- |
| **PDF** | the deck as it prints. Pages, inch budgets, the cream sheet |
| **HTML** | how it will look online. A flow, on the portal's dark ground |

His correction, 2026-09-05: *"the deck builder needs 2 views, HTML and PDF. PDF
view looks like it did before, HTML is a separate preview where i can see how it
will look online"*. The first attempt made a button that built the page and
opened Safari, which is not a view of the deck — it is leaving the app.

**The cream belongs to the PDF and stays there.** His instruction the same day.
The two designs are separate files for exactly this reason, and only the words
and the arrangement are shared.

*Push to web* sends the HTML one to the portal. Both post to routes on the
editor's own server (`/webpreview`, `/web`).

**That trap is gone with the local editor** — there is no fixed port to go stale, because there is no local server.

`tools/mcp_server.py` is the other channel — the deck builder as tools an AI can
use over stdin and stdout: read the decks, read one's shape, read and change its
words, reorder or switch off its sections, print, publish, and pull a bible's
words down again. It deliberately does not lay pages out; that is what the
editor is for.

    claude mcp add deck-builder -- /usr/bin/python3 tools/mcp_server.py

**It is local, and that is a real limit.** A deck folder is in Google Drive on
this Mac and has no address, so Notion AI cannot reach it — the portal's MCP is
a Cloudflare Worker, which is why that one is reachable from anywhere. What
Notion AI can do is write the film's page on the portal, and
`refresh_from_portal` brings it down.

### Where a picture has to live, and why

**A picture on a page of the portal is a file the portal holds.** Not a link
somewhere else. The page draws it from `/f/<film>/pic/<name>`, and there is
nowhere in that address for another server.

**Carrying pictures over from Notion — the case that catches people.** A picture
on one of his Notion pages is served from a signed address that **expires within
the hour**. Linking it makes a page that works while you are looking at it and is
broken by the afternoon, which is worse than one that never worked, because
nobody finds out until a crew member opens it on a shoot day.

So an agent writing a bible out of Notion does this, per picture:

1. Download the bytes from Notion.
2. Send them through the portal's `add_document` with `kind: picture`.
3. Write the name it hands back: `![The alley](a1b2….jpg)`.

The same picture sent twice costs nothing and makes one copy, so there is no
reason to be careful about repeats. **Never put a `notion.so`, `amazonaws.com`
or `prod-files-secure` address in a page** — `pageFrom` drops it and says so,
which is the only reason a mistake here is noisy rather than silent.

`refresh.py` on the hub side does the same thing for anything ticked `Hub` in
Notion: it mirrors the pictures into the film's own media before writing the
page. Either road ends with a picture the portal holds.

**Adding a picture of your own.** A bible's frames come off the portal, so they
already have names there. Anything you add — a still dropped into
`img/<section>/`, a reference off the desktop — has none, and until it does the
web page cannot point at it. **Push to web puts it there**: it is stored by its
own contents, written into `img/portal.json`, and linked. Sending the same
picture twice costs nothing and makes one copy.

Before that it appeared in the PDF and not on the website, which is the worst
kind of difference between two outputs of one deck.

**Nothing here authors anything.** Edit the bible in Notion or through an AI,
press Rebuild Bible, and the PDF matches the website. There is no second copy
to keep in step, which is the whole point of it.

Three things worth knowing before changing it:

- **Pagination is Chrome's.** A deck packs rows into pages by measuring inches
  because its grid is budgeted per page; a bible does not need that, and
  `break-inside: avoid` on a picture row is shorter and more honest than
  re-implementing it. The one thing computed here is a row's height, from real
  aspect ratios, so pictures side by side line up.
- **The paper is merged underneath.** Chromium prints no `body` background, and
  a `position: fixed` element does not fix it either — it is clipped to the
  page's margin box, and two prints of his own bible came out as white sheets
  with a black rectangle floating in them. `paint_under` renders a one-page PDF
  of solid colour and merges it below, borrowing `tools/merge.py` from the deck
  renderer rather than keeping a second copy.
- **The bucket is reached the way `hub/refresh.py` reaches it** — `wrangler r2
  object get --remote`, with his own credentials, using the hub's own wrangler.
  Nothing to install and no token to keep.

## Starting a new deck

Same design as an existing one, placed in that project's folder:

```bash
python3 tools/new_deck.py witch-pricker \
  --from ".../outbound/decks/pitch-deck" \
  --in ".../projects/witch-pricker/1-creative"
```

Leave off `--in` and it lands in `portfolio/outbound/decks/`. Either way it is
registered, so it shows up in the launcher.

A new look: put the reference PDF in `~/Developer/deck-references/`, then ask —
*"new deck from this Notion page, in the style of `rope-look-book.pdf`"*. What
changes is `theme.json` and `template.html`. The editor, the render pipeline
and the text round-trip are unchanged.

## What the theme controls

Page size drives the layout maths, so a 20×11.2in landscape look book packs
rows differently from an 8.5×11 portrait deck without any code change.

- `page` — width, height, CSS page size
- `grid` — gap, and how much image height fits on a project's first page, a
  continuation page, and a full-bleed grid page. Set these from how much
  furniture the template puts on each.
- `colors.paper` — painted as a full-page underlay, since Chromium will not
  print a body background
- `project_notes` — the line under each project's images
- `section_labels` — what the editor calls each section

## Text

`text.md` mirrors a Notion page. Edit either, then ask me to pull it down and
rebuild. Keys are `### section.kindN` headings matching `data-t` attributes in
the template.

Notion auto-links anything that looks like a domain, so a key such as
`contact.bio1` comes back as a markdown link. The parser strips those. It also
restores `ACME\CO`, whose backslash Notion eats.

## Tools

| | |
| --- | --- |
| `tools/render.py <deck>` | build the PDF |
| `tools/new_deck.py <name> [--from <deck>] [--in <parent>]` | scaffold a folder |
| `tools/registry.py list\|add <folder>` | which decks the launcher shows |
| `tools/deckcore.py` | config, image scanning, row packing |
| `tools/text_io.py` | markdown round-trip |
| `mac/build.sh` | rebuild Deck Editor.app |

Needs ImageMagick, a headless Chrome, and `pypdf`.
