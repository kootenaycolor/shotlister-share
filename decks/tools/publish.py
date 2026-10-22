#!/usr/bin/env python3
"""Build a deck's web page, and put it on the portal.

    python3 publish.py <deck-folder> [--local]

The other output. `render.py` makes the PDF from `template.html`; this makes a
page from `web.html`, out of the **same** `deck.json` and the **same**
`text.md`. Change a word or reorder a picture in Deck Editor and both follow.

His rule, 2026-09-05: the website shows the same styling, not the same format.
So the two templates share tokens, type and order, and nothing else — no page
budgets, no row packing, no page numbers. A picture row here keeps its
proportions and simply gets narrower; on a phone it stacks.

`--local` writes the page and stops, for previewing. Without it the page is put
beside the film on the portal, where `your-domain.example` serves it.
"""

import hashlib
import json
import time
import shutil
import re
import subprocess
import tempfile
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
from deckcore import Deck, load_dims  # noqa: E402
from text_io import parse_markdown, inject  # noqa: E402
from render import prepare_images, pull_heads, split_sections  # noqa: E402
from arrangement import Arrangement, bands  # noqa: E402
import web_design  # noqa: E402

# **The hub is a sibling now, not an address.** Until the fold of 2026-09-06
# this reached across to `~/Developer/shotlister/hub` by absolute path, which is
# how one expired Cloudflare login took down two programs at once and did it
# silently. It is the same repo, so it is the same tree.
HUB = Path(__file__).resolve().parents[2] / "hub"
BUCKET = "shotlister"

# **His two laws about a row, in the one number they both need.** Nothing
# skinnier than 2.40:1. Kept in step with `WIDEST` in `hub/public/deck.js`: the
# editor and the press publish the same page, and a row capped at one number
# here and another there is the drift this pair exists to stop.
WIDEST = 2.4


def say(*a):
    print(*a, flush=True)


def split_web(tpl):
    """Head, sections, tail — without needing a `</body>`.

    `render.py`'s splitter looks for one because a print template is a whole
    document. A web page here is a *fragment*: it is served inside the portal's
    own page, which brings its own `<html>` and `<body>`, so there is no closing
    tag to find and the print splitter stops with `substring not found`.
    """
    first = tpl.index("<!--SECTION:")
    head, rest = tpl[:first], tpl[first:]
    at = rest.rindex("</div></div>")
    body, tail = rest[:at], rest[at:]
    parts = re.split(r"<!--SECTION:([a-z_]+)-->", body)
    return head, {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}, tail


def portal_names(deck):
    """What each local picture is called on the portal, as `bible.py` wrote it.

    **Read, never derived.** They are not uploaded again — every frame was
    pulled off the portal and is still served there at `/f/<film>/pic/<name>`.
    The first version worked the name out by stripping the ordering prefix off
    the local filename, which was wrong the moment the folder held anything from
    an older run: every `src` on the published page named a picture the portal
    had never heard of, and the page came out with holes where the frames go.
    """
    try:
        return json.loads((deck.dir / "img" / "portal.json").read_text())
    except (OSError, ValueError):
        return {}


def web_rows(keys, ars, min_sum, max_per_row):
    """Re-pack a group's pictures for a screen.

    **The print rows cannot be reused here, and that was the bug.** On paper a
    row of one is a full-bleed plate on a tall sheet; in a browser the same row
    is one picture across the whole column, and a 4:3 frame becomes three
    quarters of a metre of screen. His note, 2026-09-05: *"for the html version
    avoid tall photos completely, and never crop images super skinny, keep them
    smaller and more horizontal"*.

    So a row here is filled until the aspect ratios in it add up to `min_sum`.
    A row's height is the column width divided by that sum, which makes
    `min_sum` a direct height cap: at 3.4 no row is ever taller than about a
    third of the column. Nothing is cropped to reach it — the widths stay
    exactly proportional to each picture's own shape, and a row that cannot
    reach the sum is narrowed instead, so a lone frame ends up smaller rather
    than taller.
    """
    items = list(zip(keys, ars))
    if not items:
        return []

    # **Decide how many rows first, then divide evenly.** Filling greedily and
    # narrowing whatever is left over is what put the blank space in — his note,
    # 2026-09-05: *"make sure that there's not really a lot of awkward blank
    # space between images"*. A greedy pass leaves the tail short by however
    # much it happens to be short by, and a short row is drawn narrow, so the
    # right-hand edge of a group goes ragged for no reason a reader can see.
    #
    # Choosing the row count up front and then balancing means every row lands
    # near the target, so every row fills the column and nothing is cropped to
    # make it. The heights vary by a few per cent instead, which is what a
    # gallery is supposed to look like.
    total = sum(a for _, a in items)
    # **Round down, and never ask for more rows than there are pairs.**
    # Rounding up asks for one row more than the pictures can fill, and the
    # arithmetic then has to put a single picture on a line of its own — which
    # is drawn at half width and is precisely the awkward gap he was pointing
    # at. Rounding down makes the last row hold three instead, which is shorter
    # than the others rather than emptier.
    want = max(1, int(total // min_sum))
    if len(items) >= 2:
        want = min(want, len(items) // 2)
    want = max(1, want)
    while len(items) / want > max_per_row:
        want += 1

    # Contiguous partition into `want` runs, balanced by aspect sum. Small
    # numbers — a section is a dozen pictures — so the plain dynamic program is
    # instant and exact, and there is no need to be clever.
    n = len(items)
    best = {(0, 0): (0.0, [])}
    target = total / want
    for r in range(1, want + 1):
        for end in range(r, n - (want - r) + 1):
            take = None
            for start in range(r - 1, end):
                if (start, r - 1) not in best:
                    continue
                cost, cuts = best[(start, r - 1)]
                run = sum(a for _, a in items[start:end])
                if end - start > max_per_row:
                    continue
                here = cost + (run - target) ** 2
                if take is None or here < take[0]:
                    take = (here, cuts + [end])
            if take:
                best[(end, r)] = take
    cuts = best.get((n, want), (0.0, [n]))[1]
    rows, at = [], 0
    for cut in cuts:
        rows.append(items[at:cut])
        at = cut
    if at < n:
        rows.append(items[at:])
    return [r for r in rows if r]


def web_plan(deck, slug, order, imgs, min_sum, max_per_row):
    """The rows this section wants on a screen, and how loud each one is.

    **His arrangement first, arithmetic only as a fallback.** When the folder
    holds an `arrangement.json` the grouping and the emphasis are his, and this
    honours them: a group is a row, and a group too wide for a screen splits
    evenly rather than shedding a stray onto a line of its own.

    Without one, the old behaviour stands — every picture in the section is
    flattened into one list and re-packed by aspect sum. That is what threw the
    hero away: `order` deliberately discards which pictures were on a line
    together, so nothing downstream could know that one of them had been given
    a band of its own.
    """
    seen = set(order)
    try:
        arr = Arrangement.load(deck.dir / "arrangement.json")
    except (OSError, ValueError, KeyError):
        arr = None
    if arr:
        section = next((s for s in arr.live if s.id == slug), None)
        if section and section.groups:
            out = []
            for keys, loud in bands(section, "web"):
                cells = [(k, imgs[k].get("ar") or 16 / 9) for k in keys if k in seen]
                if cells:
                    ratio = next((g.ratio for g in section.groups
                                  if any(k in g.pictures for k in keys)), "")
                    out.append((cells, loud, ratio))
            if out:
                return out
    shapes = [imgs[k].get("ar") or 16 / 9 for k in order]
    return [(packed, None, "") for packed in web_rows(order, shapes, min_sum, max_per_row)]


def frames(deck, data, imgs, paths, local, project=None, webimgs=None):
    named = portal_names(deck)
    webimgs = webimgs or {}
    webhave = web_named(deck)
    webfresh = {}
    missing = MISSING
    fresh = {}
    """Each group's rows, as a flow.

    **The order is his, the rows are the medium's.** The editor decides which
    pictures come in what order; on paper `fit_page` measures inches to land
    them on the sheet, and here `web_rows` packs them so no row is ever tall.
    Each picture takes width in proportion to its own shape, so the heights
    agree at any width without anybody knowing how wide it is.
    """
    web = deck.theme.get("web", {})
    min_sum = float(web.get("min_row_ar", 3.4))
    max_per_row = int(web.get("max_per_row", 4))
    out = {}
    for p in data.get("projects", []):
        slug = re.sub(r"[^a-z_]+", "_", str(p.get("slug", "")).lower())
        order = [k for page_rows in p.get("pages", []) for row in page_rows
                 for k in row if k in imgs]
        rows = []
        for packed, loud, ratio in web_plan(deck, slug, order, imgs, min_sum, max_per_row):
            if True:
                keys = [k for k, _ in packed]
                shapes = [a for _, a in packed]
                total = sum(shapes) or 1
                # A row that does not reach the sum is narrowed, never stretched:
                # that is what keeps a single 16:9 frame from going full width
                # and half a screen tall.
                # A row that cannot reach the sum is narrowed rather than made
                # taller — except when it is the only row in the group, where
                # there is nothing for it to line up with and narrowing just
                # looks like a mistake.
                span = min(1.0, total / min_sum)
                # **Close enough is full width.** A row that reaches most of the
                # target is drawn narrow for a difference nobody can see as
                # anything but a ragged edge; letting it fill makes it a little
                # taller than its neighbours, which is what a gallery does
                # anyway. Only a row that falls badly short stays narrow, and a
                # group that is one row has nothing to line up with at all.
                # **A hero fills the width, whatever its shape says.** One 16:9
                # frame sums to 1.78 against a target of 3.4, so the rule above
                # would draw the loudest picture in the section at half width —
                # which is how the projector-face shot, a full-bleed plate on
                # page 2 of the PDF, arrived on the website as one cell in a
                # flat grid of twelve. Emphasis is his, and it outranks the
                # arithmetic.
                if span > 0.7 or loud == "hero" or (
                        len(rows) == 0 and len(packed) == len(order)):
                    span = 1.0
                cells = []
                for k, ar in zip(keys, shapes):
                    # **Relative to the film, not to this file.** The page is
                    # served at `/f/<film>/<slug>`, so `pic/x.jpg` resolves to
                    # `/f/<film>/pic/x.jpg` — which the portal already answers.
                    # **Two homes for the same picture.** Published, it is
                    # served by the portal beside the film — the page sits at
                    # `/f/<film>/<slug>`, so `pic/x.jpg` resolves there. In the
                    # editor's own preview the page is served from
                    # `/build/web/page.html`, so `../img/work/…` reaches the
                    # copies `prepare_images` already made. A `file://` src
                    # cannot be used: the page is loaded over http and the
                    # browser refuses to mix the two.
                    if local:
                        src = "../" + webimgs.get(k, imgs[k])["src"]
                    else:
                        rel = str(Path(paths[k]).relative_to(deck.dir))
                        # **The web copy, always — not the film's own file.**
                        # The page used to point straight at whatever the film
                        # held, which is how it came to weigh 20.8 MB. The copy
                        # is content-addressed like everything else, so its name
                        # is its bytes: unchanged pictures cost no upload, and a
                        # changed one gets a new name by itself.
                        light = webimgs.get(k)
                        on_portal = webhave.get(rel) if light else None
                        want = (sha_of(deck.build_dir / light["src"])
                                if light else None)
                        if light and on_portal != want:
                            on_portal = upload(project, deck.build_dir / light["src"]) \
                                if project else None
                            if on_portal:
                                webhave[rel] = on_portal
                                webfresh[rel] = on_portal
                        if not on_portal:
                            # Nothing light to send: fall back to whatever the
                            # film already holds rather than leaving a hole.
                            on_portal = named.get(rel)
                            if not on_portal and project:
                                on_portal = upload(project, deck.build_dir / imgs[k]["src"])
                                named[rel] = on_portal
                                fresh[rel] = on_portal
                                say(f"  put {Path(rel).name} on the portal")
                        if not on_portal:
                            missing.add(rel)
                            continue
                        src = f"pic/{on_portal}"

                    # **Said on the element, not in a stylesheet.** The editor
                    # writes every layout decision inline so that what he looks
                    # at and what publishes cannot drift (see the head of
                    # `hub/src/editor.js`). The press publishes the same page,
                    # so it has to speak the same way — otherwise a re-print
                    # silently puts the old drift back, and the fault he
                    # reported on 2026-09-06 returns without anybody touching
                    # the editor.
                    wide = (f'style="width:auto;aspect-ratio:min({ratio}, {WIDEST})"'
                            if ratio else f'style="width:{ar / total * 100:.3f}%"')
                    cells.append(f'<figure data-key="{k}" {wide}>'
                                 f'<img src="{src}" alt="" loading="lazy" decoding="async"></figure>')
                # **The row carries its own shape.** With `aspect-ratio` set
                # from the ratios in it, the stylesheet can cap a row against
                # the *screen* rather than the column — which is the only cap
                # that means anything to someone scrolling on a phone. The
                # browser narrows the row to obey the cap, so nothing is ever
                # cropped to fit.
                # **A row of one says so.** On a phone the rows break into a
                # grid, and a lone picture is the one case that must not be
                # halved — it has nothing to sit beside.
                solo = " solo" if len(cells) == 1 else ""
                if ratio:
                    # **Even cells, cropped to one shape.** His note, 2026-09-06:
                    # keep the whole top grid 4:3. A contact grid is not a row of
                    # true shapes — it is a grid, and every cell the same.
                    rows.append(f'<div class="frow even" style="--cells:{len(cells)};'
                                f'--cell:{ratio};display:grid;'
                                f'grid-template-columns:repeat({len(cells)},minmax(0,1fr));'
                                f'aspect-ratio:auto;width:100%">{"".join(cells)}</div>')
                else:
                    # His two laws, on the element: nothing skinnier than
                    # 2.40:1, and a lone frame held to a measure rather than
                    # run full bleed.
                    box = ("width:66%;margin-left:auto;margin-right:auto"
                           if len(cells) == 1 else f"width:{span * 100:.2f}%")
                    rows.append(f'<div class="frow{solo}" style="--ar:{total:.4f};'
                                f'aspect-ratio:min({total:.4f}, {WIDEST});'
                                f'{box}">{"".join(cells)}</div>')
        if rows:
            # **The block says which section it is**, so the editor can put its
            # own rows back in the right place without knowing anything about
            # the design that surrounds them.
            out[f"__p_{slug}__"] = (f'<div class="frames" data-section="{slug}">'
                                    f'{"".join(rows)}</div>')
    for note_name, added in (("web.json", webfresh), ("portal.json", fresh)):
        if not added:
            continue
        note = deck.dir / "img" / note_name
        try:
            have = json.loads(note.read_text())
        except (OSError, ValueError):
            have = {}
        have.update(added)
        note.parent.mkdir(parents=True, exist_ok=True)
        note.write_text(json.dumps(have, indent=1) + "\n")
        say(f"  sent {len(added)} picture{'' if len(added) == 1 else 's'} at web size"
            if note_name == "web.json"
            else f"Recorded {len(added)} new picture{'' if len(added) == 1 else 's'}.")
    return out


# **Only in the preview, never in what is published.** The live page is served
# to a crew member inside a signed-in portal; an editing handler there would be
# both useless and a hole. `pageHtmlOf` strips scripts anyway — this is the
# other half of that rule, kept on this side so nothing depends on it.
EDITABLE = """
<style>
  .deckweb [data-t]{outline:1px dashed transparent;outline-offset:3px;
                    transition:outline-color .12s ease}
  .deckweb [data-t]:hover{outline-color:rgba(125,164,255,.45)}
  .deckweb [data-t]:focus{outline:1px solid #7DA4FF;outline-offset:3px}
  #saidso{position:fixed;left:50%;bottom:22px;transform:translateX(-50%);
          background:#181818;color:#D9D9D9;border:1px solid rgba(255,255,255,.14);
          border-radius:999px;padding:7px 15px;font:12px/1 system-ui;opacity:0;
          transition:opacity .18s ease;pointer-events:none;z-index:9}
  #saidso.on{opacity:1}
</style>
<div id="saidso"></div>
<script>
(function () {
  var note = document.getElementById("saidso");
  var say = function (t) {
    note.textContent = t; note.classList.add("on");
    clearTimeout(say.t); say.t = setTimeout(function(){ note.classList.remove("on"); }, 2200);
  };
  var dirty = {};
  document.querySelectorAll(".deckweb [data-t]").forEach(function (el) {
    el.setAttribute("contenteditable", "plaintext-only");
    el.spellcheck = false;
    el.addEventListener("focus", function () { el.dataset.was = el.textContent; });
    el.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); el.blur(); }
      if (e.key === "Escape") { el.textContent = el.dataset.was || ""; el.blur(); }
    });
    el.addEventListener("blur", function () {
      if (el.textContent === el.dataset.was) return;
      dirty[el.getAttribute("data-t")] = el.textContent.trim();
      save();
    });
  });
  function save() {
    var items = Object.keys(dirty).map(function (k) { return {key: k, value: dirty[k]}; });
    if (!items.length) return;
    dirty = {};
    fetch("/text", {method: "POST", headers: {"content-type": "application/json"},
                    body: JSON.stringify({items: items})})
      .then(function (r) { return r.json(); })
      .then(function (g) { say(g.ok ? "Saved — the PDF has it too" : "Could not save"); })
      .catch(function () { say("Could not save"); });
  }
  say("Click any words to edit them");
})();
</script>
"""


MISSING = set()


def web_images(deck, paths, max_px, quality):
    """The same pictures again, at a size a browser should be handed.

    **Why a second set at all**, when `prepare_images` already makes one. That
    one is sized for paper and is shared with the press; a sheet and a screen do
    not want the same file, which is the seventh of the medium rules in
    `decks/PRINT-AND-WEB.md`. Keeping them apart means the web can be made
    lighter without quietly softening the print.

    **What it is worth.** Measured on his bible, 2026-09-08: the published page
    asked for 38 distinct pictures weighing **20.8 MB**, because it pointed at
    the film's own stored copies and those are kept at near-lossless quality —
    one is 800x600 and weighs 793 KB, another 1368x1026 weighs 1.9 MB. His
    report: *"images are slower to load on the mobile HTML version and come up
    with, like, blank empty squares… sometimes it takes a while or another
    refresh."* Both halves of that are this. The blank square is the picture not
    arrived yet; the one that needs a refresh is iOS dropping decoded images
    when a page holds more than Safari will keep, and a 2880-pixel-wide frame
    costs 13 MB of memory decoded however small it is drawn.

    Written beside the print set rather than in it, so neither can tread on the
    other. `prepare_images` is left alone on purpose: it lives in `render.py`,
    which the press and another thread both had open the day this was written.
    """
    out = deck.build_dir / "img" / "web"
    out.mkdir(parents=True, exist_ok=True)
    made = {}
    for k, src in paths.items():
        dst = out / f"{k}.jpg"
        if not (dst.exists() and dst.stat().st_mtime >= Path(src).stat().st_mtime):
            subprocess.run(["magick", src, "-auto-orient", "-resize",
                            f"{max_px}x{max_px}>", "-quality", str(quality),
                            "-strip", "-interlace", "Plane", str(dst)],
                           capture_output=True)
        if dst.exists():
            made[k] = {"src": f"img/web/{dst.name}"}
    return made


def web_named(deck):
    """What each web copy is called on the portal. Its own record, deliberately.

    `portal.json` says what the *originals* are called and the editor's shelf
    reads it; this is a separate note so neither has to know about the other.
    """
    try:
        return json.loads((deck.dir / "img" / "web.json").read_text())
    except (OSError, ValueError):
        return {}


def sha_of(path):
    """The name a file would have on the portal — its own bytes."""
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:32] + ".jpg"
    except OSError:
        return None


def upload(project, path):
    """Put a picture on the portal and hand back the name it now has there.

    **The gap this closes.** A bible's pictures arrive from the portal, so they
    already have names there. Anything he adds himself — a frame dropped into
    `img/<section>/`, a reference off his desktop — has none, and the published
    page simply left it out. It appeared in the PDF and not on the website,
    which is the worst kind of difference between two outputs of one deck.

    Stored **content-addressed**, the same bargain every picture on the portal
    strikes: the name is the file's own hash, so sending the same picture twice
    costs nothing and makes one copy. The prepared JPEG is what goes up rather
    than the original — it is already sized for a page, and a look book full of
    untouched camera files would be a slow website.
    """
    data = Path(path).read_bytes()
    name = hashlib.sha256(data).hexdigest()[:32] + ".jpg"
    got = subprocess.run(wrangler() + ["r2", "object", "put",
                                       f"{BUCKET}/p/{project}/docs/{name}",
                                       "--file", str(path), "--remote",
                                       "--content-type", "image/jpeg"],
                         capture_output=True, text=True)
    if got.returncode != 0:
        raise SystemExit("Could not put a picture on the portal:\n"
                         + (got.stderr or got.stdout)[-400:])
    return name


def block_order(deck, data, sections):
    """Which of the design's blocks go out, and in what order.

    **The design's own order, not `deck.json`'s.** `web.html` is written for this
    deck in Notion's order, so its blocks already stand in the right sequence.
    The order used to be read off `deck.json` instead — a print artefact that
    `press.py` rewrites from the record every time it prints, listing only the
    sections it prints. On 2026-09-07 that list was 17 ids long against the
    design's 30, and a publish sent the page out with fourteen of its word
    blocks missing. The arrangement decides only what is *off*: a picture block
    whose section is off or unknown, and a word block whose section is off.
    Without an arrangement the old reading of `deck.json` stands.
    """
    try:
        arr = Arrangement.load(deck.dir / "arrangement.json")
    except (OSError, ValueError, KeyError):
        arr = None
    if not arr or not arr.sections:
        order = [s["id"] for s in data.get("sections", []) if s.get("on", True)]
        return [o for o in order if o in sections] or list(sections)
    known = {s.id for s in arr.sections}
    off = {s.id for s in arr.sections if not s.on}

    def shown(sid):
        m = re.fullmatch(r"__p_(.+)__", sid)
        if m:
            return m.group(1) in known and m.group(1) not in off
        return sid not in off
    return [sid for sid in sections if shown(sid)]


def eager_first(doc, n=8):
    """The pictures already on the screen are not lazy ones.

    Every frame carries `loading="lazy"`, which is right for a document of
    sixty-five photographs and wrong for the handful you are looking at the
    moment it opens: the browser waits until they are nearly in view before it
    starts, so the first thing anybody sees is the empty boxes waiting to be
    filled. Measured at 390px, 2026-09-08: **seven pictures sat above the fold
    and all seven were lazy** — eight are made eager, so the first screenful is
    covered at any of the widths this page is read at. His report — *"blank empty squares"* — is partly
    that and partly the weight, and both are worth fixing.

    Said here rather than in `frames`, because only here is the order the one
    the reader actually meets: `block_order` has run.
    """
    return doc.replace(' loading="lazy"', ' loading="eager" fetchpriority="high"', n)


def build(deck, local=False, project=None):
    web = deck.dir / "web.html"
    if not web.exists():
        raise SystemExit("This deck has no web.html. Re-run bible.py, or write one.")
    data = json.loads(deck.deck_file.read_text())
    groups, paths, labels = deck.scan()
    out = deck.theme.get("output", {})
    imgs = prepare_images(deck, paths, out.get("max_px", 1250), out.get("quality", 80))
    # **The screen's own size.** A sheet is a fixed width for ever and a page is
    # every width; the theme may say so, and 1600 wide at 78 is the default
    # because it is about four times what a phone draws and twice what the
    # column ever is on a desk.
    wcfg = deck.theme.get("web", {})
    webimgs = web_images(deck, paths, int(wcfg.get("max_px", 1600)),
                         int(wcfg.get("quality", 78)))

    head, sections, tail = split_web(web.read_text())
    sections.update(frames(deck, data, imgs, paths, local, project, webimgs))
    if deck.text_md.exists():
        values = parse_markdown(deck.text_md.read_text())
        for sid in sections:
            sections[sid] = inject(sections[sid], values)

    order = block_order(deck, data, sections)
    doc = head + "".join(sections.get(i, "") for i in order) + tail
    doc = eager_first(doc)

    if local:
        doc += EDITABLE
    # **Two shapes, two files.** They differ in the only two things that
    # matter: the preview points at pictures the editor can serve and carries
    # the editing handler; the published one points at `pic/…`, which only
    # resolves beside the film. Writing both to one name meant a publish left
    # the app showing a page whose every picture was a broken link and whose
    # words could not be edited — which is exactly what "looks nothing like the
    # website" turns out to mean.
    where = deck.build_dir / "web"
    where.mkdir(exist_ok=True)
    out = where / ("preview.html" if local else "page.html")
    out.write_text(doc)
    say(f"Built {len(order)} blocks into {out}")
    # **A picture the portal cannot name is said, not silently dropped.** A page
    # with holes in it reads as the website being broken.
    if MISSING and not local:
        say(f"{len(MISSING)} pictures have no portal name and were left out.")
        say("Run bible.py on this folder to pull them again.")
    return out, imgs, paths


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    deck = Deck(sys.argv[1])
    local = "--local" in sys.argv
    # **The film is worked out first now**, because a picture with no name on
    # the portal is put there while the page is being built, and that needs to
    # know which film it belongs to.
    project = None
    cfg = deck.dir / "bible.json"
    if not local and cfg.exists():
        from bible import project_for
        project = project_for(json.loads(cfg.read_text()).get("film", ""))
    # **What he did in the editor comes down before anything goes up.** Unless
    # `--from-folder` says the folder is meant to win this once — and then what
    # would be lost is said first, so that is never a surprise.
    record = None
    if project:
        slug0 = json.loads(cfg.read_text()).get("page", "bible")
        record = fetch_record(project, slug0)
        if record and "--from-folder" not in sys.argv:
            w, n = adopt_portal(deck, record)
            if w or n:
                say(f"Took the portal's copy first: {w} words and {n} sections changed here to match what he did in the editor.")
            else:
                say("The portal and this folder agree; nothing to take.")
        elif record:
            here = parse_markdown(deck.text_md.read_text()) if deck.text_md.exists() else {}
            lost = {k: v for k, v in (record.get("words") or {}).items()
                    if k in here and _plain(here[k]) != _plain(v)}
            say(f"--from-folder: the folder wins. {len(lost)} words on the portal will be overwritten"
                + (": " + ", ".join(sorted(lost)[:8]) if lost else "."))
    # **After the portal's copy comes down, because that copy is what can bring
    # file names back in** — a record published before this ran holds them.
    swapped, unplaced = normalize_arrangement(deck)
    if swapped:
        say(f"Renamed {swapped} pictures in the arrangement from file names to the keys the portal reads.")
    if unplaced:
        say(f"{len(unplaced)} pictures in the arrangement match no file in this folder, e.g. {unplaced[0]}")
    page, imgs, paths = build(deck, local, project)
    if local:
        say("Local only. Open it in a browser to look at it.")
        return
    if not project:
        raise SystemExit("No bible.json, so nothing here knows which film to publish to.")
    cfgd = json.loads(cfg.read_text())
    slug = cfgd.get("page", "bible")
    key = f"p/{project}/pages/{slug}.html"
    subprocess.run(wrangler() + ["r2", "object", "put", f"{BUCKET}/{key}",
                                 "--file", str(page), "--remote",
                                 "--content-type", "text/html; charset=utf-8"],
                   check=True, capture_output=True)
    # **The document is not the page.** The portal only reads this file after it
    # has decided the address exists, and it decides that from the film's own
    # list of sections. Without a row there, `/f/<film>/<slug>` answers "No such
    # page" and never looks — so publishing wrote a real file nobody could
    # reach and said it had worked. See the row of the same name in Notion.
    named = cfgd.get("name") or slug.replace("-", " ").title()
    made = ensure_section(project, slug, named)
    say(f"Published to your-domain.example/f/{project}/{slug}")
    if made:
        say(f"  and put “{named}” on the film's rail, which had no row for it")
    filed = file_pdf(project, deck, named)
    if filed:
        say(f"  and filed the {filed} MB PDF under the film's Documents")
    try:
        from arrangement import Arrangement as _A
        arr = _A.load(deck.dir / "arrangement.json")
        words = parse_markdown(deck.text_md.read_text()) if deck.text_md.exists() else {}
        # **What changed up there, before this overwrites it.** Said, never
        # applied: a word he changed here and a word an AI changed there are
        # both real, and choosing between them silently is how his Drive folder
        # and his website came apart in the first place.
        differs = pull_words(project, slug, words)
        for key in list(differs)[:6]:
            say(f"  note: “{key}” was changed on the portal since this folder last published")
        if differs:
            say(f"  {len(differs)} in all — pull them into text.md if you want them kept.")
        shelf = {}
        for key, one in (imgs or {}).items():
            rel = str(Path(paths[key]).relative_to(deck.dir)) if key in paths else ""
            on_portal = portal_names(deck).get(rel, "")
            if on_portal:
                shelf[key] = {"name": on_portal, "ar": round(one.get("ar") or 16 / 9, 4)}
        n, w = push_record(project, deck, slug, named, arr, words, shelf,
                           keep=record if isinstance(record, dict) else None)
        say(f"  and put its {n} sections and {w} pieces of writing on the film, where an AI can reach them")
        # **And the print design, so the paper view is real.** Without this the
        # editor has nothing to draw a sheet with and says so rather than
        # pretending; with it, paper is arranged in the same place as the web.
        push_paper(project, slug, paper_kit(deck, arr, project))
        say("  and its paper design, so the sheets can be arranged in the editor")
    except (OSError, ValueError, KeyError) as e:
        say(f"  (the deck's own record was not sent: {e})")



def paper_kit(deck, arr, project=None):
    """The print design, in the shape the editor can draw sheets from.

    **Why this exists at all.** The paper view used to be an iframe of whatever
    the Mac last printed — a picture, with no handles on it. So the third of his
    three layers (*how many across, crop and page breaks are per side*) could
    only ever be set for the web, and his complaint of 2026-09-06 that *"the PDF
    has no editing controls"* was exactly right.

    What goes up is the design and nothing else: the print stylesheet, the page
    geometry out of `theme.json`, and each section's own block of words lifted
    from `template.html`. **Not one thing about where the pictures land** — that
    is his, it is decided in the editor, and it comes back down as the sheets
    the press prints.

    **A sheet's own dress travels with it.** His report, 2026-09-07: *"the PDF
    is missing a lot of the special formatting, including the glowing text and
    colored text"* — and it was the editor's paper view he meant. Three things
    were being lost between the template and the sheet on his screen:

    - The wrapper's classes. A word page is `<div class="page red">` or
      `<div class="page spec">` or `<div class="page end spec">`, and the red
      ground, the spectrum band and the mirrored ending all hang on that class.
      The kit used to hand over the block's *contents* and drop the wrapper, so
      every sheet the editor drew was the plain black one — and so was every
      sheet it published for the press. Now each block says its `cls` and its
      inline `style`, and the editor puts them on the sheet it draws.
    - `:root`. The design keeps its colours as variables on `:root`, which is
      the document's own root — and the editor draws the sheets inside a shadow
      root, where `:root` matches nothing. Every `var(--neon)` came out invalid:
      no glow, no amber italic, no red. The variables are moved onto `.page`
      here, which is where everything drawn on paper lives, in the editor and in
      the print alike.
    - The typefaces. `@font-face` points at `assets/fonts/…` beside the
      template, which resolves to nothing from the portal, so the editor set the
      sheet in Georgia. The files are put on the film and the rule is pointed at
      them, the way a picture is.
    """
    tpl = deck.template.read_text()
    css = "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", tpl, re.S))
    css = re.sub(r"(?<![\w-]):root\b", ".page", css)
    css = onto_the_sheet(css)
    css = sheet_fonts(deck, css, project)
    heads, rest = pull_heads(tpl)
    _head, blocks, _tail = split_sections(rest)

    def inner(html):
        # **A block's contents, and what its sheet wore.** The template wraps a
        # section of words in its own `<div class="page …">`; the editor draws
        # the sheet, so handing over the wrapper too would nest one page inside
        # another — but the wrapper's classes and style are the sheet's dress,
        # and they go up beside the contents so the editor can put them back.
        m = re.search(r'<div class="page([^"]*)"([^>]*)>(.*)</div>', html, re.S)
        if not m:
            return {"html": html.strip(), "cls": "", "style": ""}
        st = re.search(r'style="([^"]*)"', m.group(2) or "")
        return {"html": m.group(3).strip(), "cls": m.group(1).strip(),
                "style": st.group(1).strip() if st else ""}

    theme = deck.theme
    grid = theme.get("grid", {})
    page = theme.get("page", {})
    live = {s.id for s in arr.sections}
    return {
        "css": css,
        "theme": {
            "w": float(page.get("width_in", 8.5)),
            "h": float(page.get("height_in", 11.0)),
            "gap": float(grid.get("gap_in", 0.11)),
            "first": float(grid.get("first_budget_in", 10.5)),
            "cont": float(grid.get("cont_budget_in", 10.5)),
        },
        "foot": theme.get("frames_foot", ""),
        "alt": theme.get("alt_pages", ""),
        # A words section keeps its own id; a picture section is wrapped in the
        # `__p_…__` marker in the template and is known by the bare slug here.
        "blocks": {sid: inner(html) for sid, html in blocks.items()
                   if sid in live and inner(html)["html"]},
        "heads": {slug: {"inches": inches, **inner(html)}
                  for slug, (html, inches) in heads.items() if slug in live},
    }


def onto_the_sheet(css):
    """What the design says of `body`, said of `.page` instead.

    A print template sets its typeface, its ink and its measure on `body`, and
    in the print that is right — the sheets are the document. In the editor the
    sheets are drawn inside a shadow root with no body of their own, so a rule on
    `body` reaches nothing and the sheet inherits the portal's own face: his
    Playfair bible was set in Rethink Sans there, and looked like a different
    design. So a rule addressed to `html` or `body` is re-addressed to `.page`,
    and its `background` is dropped on the way — the sheet paints its own
    ground, and the document's is the editor's table, not the design's.
    """
    def move(m):
        decls = [d.strip() for d in m.group(1).split(";") if d.strip()
                 and not d.strip().lower().startswith("background")]
        return ".page{" + ";".join(decls) + "}" if decls else ""
    # Anchored to the start of a rule — the start of the sheet or the close of
    # the rule before — so `.body{…}` and `tbody{…}` are left alone.
    return re.sub(r"(?:^|(?<=}))\s*(?:html|body)(?:\s*,\s*(?:html|body))*\s*{([^}]*)}",
                  move, css, flags=re.M)


FONT_TYPES = {".ttf": "font/ttf", ".otf": "font/otf", ".woff": "font/woff",
              ".woff2": "font/woff2"}


def sheet_fonts(deck, css, project):
    """Put the design's own typefaces where the editor can reach them.

    Every `url(assets/…)` in the print stylesheet names a file beside the
    template. From the portal that address is nothing, so the editor's sheet
    fell back to Georgia while the print set Playfair — the two looked like two
    designs when they were one. Each file goes up under the film's documents,
    named by its own contents like every picture, and the rule is pointed at it
    the way the editor points at a picture: `../pic/<name>`, one level down
    from the film. With no film to publish to, the stylesheet is left alone.
    """
    if not project:
        return css

    def swap(m):
        rel = m.group(2)
        src = deck.dir / rel
        kind = FONT_TYPES.get(src.suffix.lower())
        if not kind or not src.exists():
            return m.group(0)
        data = src.read_bytes()
        name = hashlib.sha256(data).hexdigest()[:32] + src.suffix.lower()
        got = subprocess.run(wrangler() + ["r2", "object", "put",
                                           f"{BUCKET}/p/{project}/docs/{name}",
                                           "--file", str(src), "--remote",
                                           "--content-type", kind],
                             capture_output=True, text=True)
        if got.returncode != 0:
            say(f"  (a typeface did not go up: {src.name})")
            return m.group(0)
        return f"url({m.group(1)}../pic/{name}{m.group(1)})"

    return re.sub(r"url\((['\"]?)(assets/[^'\")]+)\1\)", swap, css)


def push_paper(project, slug, kit):
    """Put the print design on the film, beside the deck's record."""
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(kit, f)
        where = f.name
    try:
        got = subprocess.run(wrangler() + [
            "r2", "object", "put", f"{BUCKET}/p/{project}/decks/{slug}.paper.json",
            "--file", where, "--remote",
            "--content-type", "application/json; charset=utf-8"], capture_output=True, text=True)
        if got.returncode != 0:
            raise SystemExit("Could not put the paper design on the portal:\n"
                             + (got.stderr or got.stdout)[-400:])
    finally:
        Path(where).unlink(missing_ok=True)


def push_record(project, deck, slug, name, arr, words, pictures=None, keep=None):
    """Put the deck's words and order on the film, where an AI can reach them.

    **The half of a deck that is not the design.** His plan of 2026-09-05 puts a
    deck's content server-side so Notion AI can work on it; the design stays
    written for the deck, and the arrangement stays his, done by hand where he
    can see it. So what goes up is the sections in order, their grouping and
    emphasis as a *record* of what he chose, and every piece of writing.

    Small on purpose — a whole bible is a few dozen kilobytes, because the
    pictures are already served by the film.

    **It writes what it owns onto what is already there.** This used to build a
    fresh object and put it, which deleted every key on the portal that this
    function does not set: the crops he made per side, the Notion page linked in
    the inspector, and — once the portal began printing the PDF — how many
    frames he had put across a line. None of it was reported, because nothing
    here knew those keys existed. `keep` is the record as it was fetched at the
    start of the publish; anything in it that is not replaced below survives.
    """
    record = dict(keep or {})
    record.update({
        "version": 1, "name": name, "slug": slug,
        "sections": [s.as_json() for s in arr.sections],
        "words": words,
        # **What a picture is, not just that it is there.** The editor draws the
        # deck rather than showing a photograph of it, so it needs each frame's
        # name on the portal and its shape — a row's widths are proportional to
        # the aspect ratios in it, and without them nothing can be laid out.
        "pictures": {**(record.get("pictures") or {}), **(pictures or {})},
        "updated": __import__("datetime").datetime.utcnow().isoformat() + "Z",
    })
    tmp = Path(f"/tmp/deck-{project}-{slug}.json")
    tmp.write_text(json.dumps(record))
    subprocess.run(wrangler() + ["r2", "object", "put",
                                 f"{BUCKET}/p/{project}/decks/{slug}.json",
                                 "--file", str(tmp), "--remote",
                                 "--content-type", "application/json; charset=utf-8"],
                   check=True, capture_output=True)
    tmp.unlink(missing_ok=True)
    return len(record["sections"]), len(words)


def fetch_record(project, slug):
    """The deck's record as the portal holds it, or None if it has none."""
    got = subprocess.run(wrangler() + ["r2", "object", "get",
                                       f"{BUCKET}/p/{project}/decks/{slug}.json",
                                       "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout.strip():
        return None
    try:
        return json.loads(got.stdout)
    except ValueError:
        return None


def adopt_portal(deck, record):
    """Take what he did in the editor as the truth, before this folder builds.

    **His report, 2026-09-07:** *"if I make any manual changes to the deck, then
    use Claude to make more changes, all my manual changes are reverted."* True,
    and the reason was direction: his edits live in the deck's record on the
    portal, this folder kept its own copy of the words and the arrangement, and
    publishing pushed the folder's copy over his — reporting the difference only
    after it had already been lost. That is how his Aspect Ratio paragraph went.

    So the record comes down first. Its words go into `text.md` and its sections
    into `arrangement.json`; the folder keeps only the two designs as its own.
    A word this folder has that the portal does not is kept — a slot the design
    added since the last publish — and a portal with no sections at all leaves
    the arrangement alone. The old files go into `.history/` first, so nothing
    is destroyed, only moved. His ruling of 2026-09-05: content and order from
    Notion, arrangement and edits in the editor, the Mac is the press.

    Returns what changed, in words and in sections, so it can be said.
    """
    from arrangement import Arrangement, Section
    from text_io import words_markdown
    stamp = time.strftime("%H%M%S")
    took_words = took_sections = 0

    theirs = record.get("words") or {}
    if theirs:
        mine = parse_markdown(deck.text_md.read_text()) if deck.text_md.exists() else {}
        merged = {**mine, **theirs}
        changed = [k for k in merged if _plain(merged.get(k)) != _plain(mine.get(k))]
        if changed or set(merged) != set(mine):
            if deck.text_md.exists():
                shutil.copy(deck.text_md, deck.history / f"text-{stamp}-before-adopt.md")
            deck.text_md.write_text(words_markdown(merged))
            took_words = len(changed)

    sections = record.get("sections")
    if isinstance(sections, list) and sections:
        arr_path = deck.dir / "arrangement.json"
        try:
            was = Arrangement.load(arr_path)
        except (OSError, ValueError, KeyError):
            was = Arrangement()
        now = Arrangement([Section.of_json(s) for s in sections], was.film, was.page)
        if [s.as_json() for s in now.sections] != [s.as_json() for s in was.sections]:
            if arr_path.exists():
                shutil.copy(arr_path, deck.history / f"arrangement-{stamp}-before-adopt.json")
            now.save(arr_path)
            took_sections = sum(1 for a, b in zip(now.sections, was.sections)
                                if a.as_json() != b.as_json()) + abs(len(now.sections) - len(was.sections))
    return took_words, took_sections


def picture_lookup(deck, paths):
    """Every name a picture can be called by in a folder, mapped to its key.

    **A key is `sha1(absolute path)[:16]`, and the portal only knows keys.** A
    folder's `arrangement.json` is sometimes written by hand or by a one-off
    script that names a picture the way a person would: `pair-01/a-06OYXPMR.jpg`.
    That is the same picture, called something the portal cannot read (Ref 1561:
    Lens Character published sections full of file names, and the portal's own
    deck view found none of its pictures). So the names a folder is likely to
    use are all gathered here: the full path, the path from the deck folder, from
    its `img/` folder, and from each pool's root.
    """
    roots = [deck.dir, deck.dir / "img"]
    for pool in deck.sources.get("pools", []):
        if pool.get("root"):
            roots.append(Path(pool["root"]).expanduser())
    lookup = {}
    for key, full in paths.items():
        lookup[str(full)] = key
        for root in roots:
            try:
                lookup.setdefault(str(Path(full).relative_to(root)), key)
            except ValueError:
                pass
    return lookup


def rekey_sections(sections, lookup, keys):
    """The sections with every picture named by its key, and what could not be.

    A picture that is already a known key is left alone; one that is a file name
    the folder can place becomes its key; one that is neither stays exactly as it
    was and is reported, because inventing a key for it would put a hole in the
    page that nobody can see.
    """
    changed, lost = 0, []
    for s in sections:
        for g in s.get("groups", []):
            out = []
            for p in g.get("pictures", []):
                if p in keys:
                    out.append(p)
                elif p in lookup:
                    out.append(lookup[p])
                    changed += 1
                else:
                    out.append(p)
                    lost.append(p)
            g["pictures"] = out
    return changed, lost


def normalize_arrangement(deck):
    """Make `arrangement.json` name pictures by key, before anything reads it.

    The old files go into `.history/` first, so nothing is destroyed, only
    moved — the same promise `adopt_portal` makes. Returns (changed, unplaced).
    """
    arr_path = deck.dir / "arrangement.json"
    try:
        raw = json.loads(arr_path.read_text())
    except (OSError, ValueError):
        return 0, []
    _, paths, _ = deck.scan()
    changed, lost = rekey_sections(raw.get("sections", []), picture_lookup(deck, paths),
                                   set(paths))
    if changed:
        shutil.copy(arr_path, deck.history / f"arrangement-{time.strftime('%H%M%S')}-before-rekey.json")
        arr_path.write_text(json.dumps(raw, indent=1) + "\n")
    return changed, lost


def _plain(s):
    """The words, without the mark-up either side happens to carry."""
    s = re.sub(r"<[^>]+>", "", str(s or ""))
    s = s.replace("&amp;", "&").replace("&nbsp;", " ")
    return re.sub(r"\s+", " ", s).strip()


def pull_words(project, slug, here):
    """What an AI changed since this folder last published.

    **Report, never invent** — the project's own law, and the reason this only
    returns what differs rather than writing anything. A word changed on the
    portal and a word changed in `text.md` are both real, and deciding between
    them silently is how his Drive folder and his website came apart.
    """
    got = subprocess.run(wrangler() + ["r2", "object", "get",
                                       f"{BUCKET}/p/{project}/decks/{slug}.json",
                                       "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout:
        return {}
    try:
        theirs = json.loads(got.stdout).get("words", {})
    except ValueError:
        return {}
    return {k: v for k, v in theirs.items() if k in here and here[k] != v}


def file_pdf(project, deck, name):
    """Put the printed deck under the film's Documents, beside its page.

    **One deck, two things a person might want.** A director opening the link
    reads the page; a director who wants it on a plane takes the PDF. His plan
    of 2026-09-05 makes both the same act, so publishing files the print as
    well as the page.

    It goes up through wrangler rather than the MCP on purpose: `add_document`
    caps an upload at about six megabytes and a real bible is fifty. Named by
    its own contents, which is what the portal expects and what makes sending
    the same file twice cost nothing.
    """
    # A deck in `1-creative/decks/<deck>/z-source` keeps its current PDF one
    # level up, beside z-archive/; look there as well as in the folder itself.
    homes = [deck.dir] + ([deck.dir.parent] if deck.dir.name == "z-source" else [])
    pdfs = sorted((f for h in homes for f in h.glob("*.pdf")),
                  key=lambda f: f.stat().st_mtime, reverse=True)
    if not pdfs:
        return False
    pdf = pdfs[0]
    digest = hashlib.sha256(pdf.read_bytes()).hexdigest()[:32]
    got = subprocess.run(wrangler() + ["r2", "object", "get", f"{BUCKET}/p/{project}/front.json",
                                       "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout:
        say("  could not read the film's card — the PDF is not filed.")
        return False
    front = json.loads(got.stdout)
    docs = [d for d in front.get("documents", []) if isinstance(d, dict) and d.get("name")]
    # **Under the page's rail name, the same as the portal's press.** The deck
    # page finds its PDF by that name; a row under any other is unreachable.
    slug = json.loads((deck.dir / "bible.json").read_text()).get("page", "bible") \
        if (deck.dir / "bible.json").exists() else ""
    on_rail = next((s.get("name") for s in front.get("sections", [])
                    if isinstance(s, dict) and s.get("slug") == slug and s.get("name")), "")
    mine = {n for n in (on_rail, name, slug.replace("-", " ").title() if slug else "") if n}
    name = on_rail or name
    row = {"name": name[:140], "kind": "lookbook",
           "file": f"{digest}.pdf", "bytes": pdf.stat().st_size, "note": ""}
    if any(d.get("name") == row["name"] and d.get("file") == row["file"] for d in docs):
        return False
    subprocess.run(wrangler() + ["r2", "object", "put", f"{BUCKET}/p/{project}/docs/{digest}.pdf",
                                 "--file", str(pdf), "--remote",
                                 "--content-type", "application/pdf"],
                   check=True, capture_output=True)
    front["documents"] = [d for d in docs
                          if not (d.get("kind") == "lookbook" and d.get("name") in mine)] + [row]
    tmp = Path(f"/tmp/front-doc-{project}.json")
    tmp.write_text(json.dumps(front))
    subprocess.run(wrangler() + ["r2", "object", "put", f"{BUCKET}/p/{project}/front.json",
                                 "--file", str(tmp), "--remote",
                                 "--content-type", "application/json; charset=utf-8"],
                   check=True, capture_output=True)
    tmp.unlink(missing_ok=True)
    return round(pdf.stat().st_size / 1e6, 1)


def ensure_section(project, slug, name):
    """Make sure the film lists this page, so its address answers.

    Returns True if a row had to be made. **Stamped `by: "deck"`**, which is how
    the portal tells the three kinds apart: a page from Notion is refreshed from
    Notion, an agent's page may be rewritten by an agent, and a deck's page is
    left alone by both — his design is not something plain words may land on.
    """
    got = subprocess.run(wrangler() + ["r2", "object", "get", f"{BUCKET}/p/{project}/front.json",
                                       "--pipe", "--remote"], capture_output=True)
    if got.returncode != 0 or not got.stdout:
        # **An empty read is not an empty file.** A signed-out wrangler writes
        # its error to stderr and nothing to stdout, so treating this as "no
        # card yet" would overwrite the film's whole record with one section.
        say("  could not read the film's card — not touching its sections.")
        say("  If wrangler is signed out, `npx wrangler login` and publish again.")
        return False
    front = json.loads(got.stdout)
    rows = [s for s in front.get("sections", []) if isinstance(s, dict) and s.get("slug")]
    if any(s["slug"] == slug for s in rows):
        return False
    front["sections"] = rows + [{"slug": slug, "name": name[:60], "title": "", "by": "deck"}]
    front["updated"] = __import__("datetime").datetime.utcnow().isoformat() + "Z"
    tmp = Path(f"/tmp/front-{project}.json")
    tmp.write_text(json.dumps(front))
    subprocess.run(wrangler() + ["r2", "object", "put", f"{BUCKET}/p/{project}/front.json",
                                 "--file", str(tmp), "--remote",
                                 "--content-type", "application/json; charset=utf-8"],
                   check=True, capture_output=True)
    tmp.unlink(missing_ok=True)
    return True


def wrangler():
    local = HUB / "node_modules/.bin/wrangler"
    return [str(local)] if local.exists() else ["npx", "--yes", "wrangler@4"]


if __name__ == "__main__":
    main()
