# Checking the deck editor

Two things get checked here, and neither can be checked by reading.

**`measure.mjs` — does the editor show what the site will show?** His complaint,
2026-09-06: *"the preview panes are not an exact preview of what will be
displayed on the html website. images have more gaps."* This opens the editor
and the live page, measures every frame in both, and prints the differences.
Before the fix: 12 frames out, the worst by 392px. After: every frame the same
size.

**`drive.mjs` — do the controls work?** 72 checks that click, shift-click,
drag, sweep, crop, delete, undo and publish, the way a hand does. It catches
what reading cannot: the drop bar had no CSS anywhere in the repo and had been
invisible since the editor landed, so every drag was blind.

## Running them

```
decks/checks/rig.sh          # a local hub with one film and one deck in it
cd decks/checks && node drive.mjs && node measure.mjs shots
decks/checks/rig.sh stop
```

**It needs `playwright-core`, which is not a dependency of anything here.**
`npm i playwright-core` in this folder, and Chrome for Testing already sits in
`~/Library/Caches/ms-playwright` — both scripts point straight at it, because
the cached browser and the npm package are usually different versions and
letting playwright pick fails.

The hub it starts is **local only**, on port 8931, against a temporary bucket in
`decks/checks/state`. It never touches the real one. `rig.sh stop` frees the
port — leaving workers running is how a machine ends up with thirty-six of them
and nothing answering (Ref 758).

`pdftest.swift` and friends are not kept: what they proved is written down
instead. A WKWebView — which is all `Deck Editor.app` is — draws **nothing** for
a PDF in a frame, and a blank page for one loaded whole, while
`navigator.pdfViewerEnabled` says `true` in it. That is why the paper view
offers the file instead of embedding it there.

## After the rebuild of 2026-09-06

The editor became a rail, a canvas and an inspector, and **paper became a real
view** — drawn here from the print design rather than embedded as the last PDF.
Three things about checking it changed with that.

- **`drive.mjs` stubs its own saves.** It did not, so every run wrote to the
  local bucket and the next run started from a deck the last one had left
  behind. The audit already did this; now both do.
- **`measure.mjs` compares proportion, not pixels.** The editor draws the deck
  in a narrower column than the site does, because of the rail and the
  inspector. Raw pixels then say "12 frames differ" about a page laid out
  identically, which is a check that cries wolf. What it compares now is each
  frame's share of its column and the shape it is drawn at — which is what the
  inline styles decide and what publishing carries across.
- **The paper side is checked too.** That sheets are drawn at 8.5×11in, that
  every frame is on paper as well as on the web, that a frame on a sheet can be
  picked and arranged, and that arranging redraws the sheets.

`seed.py` now also writes a `paper.json` — the print design in the shape
`publish.py` pushes one — and `rig.sh` puts it in the bucket. Without it the
paper view says so rather than pretending.

## After the pass of 2026-09-07

Twenty-six checks were added for what driving found and what was built on it:
the zoom dial really scales the web side; a shelf tile is a tile and wears its
tick; the *Unused* tab; *Add Stills…* is a real file picker; the drawer as a
grid; Shift on the shelf picks a run and the run drags in together; a second
press on a still opens it whole; ⌘A picks the section and then the deck; ⌥←/→
swap a frame along its row; *Link…* is a field; the menu offers emphasis; and
the deck stays on screen at 1000px and at 900px, the app's own smallest.

Two things about driving that cost time and are worth knowing:

- **`rig.sh` now detaches the hub with `nohup`.** As a plain background job it
  died the moment the shell that ran the script exited — every time, when the
  script is run by an agent — and the next check found nothing listening.
- **A `dblclick` never fires on an element whose `pointerdown` was prevented**,
  and the shelf has to prevent it or the browser drags the picture itself. The
  second press is read by timing, the way the canvas already does it.
