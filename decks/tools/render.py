#!/usr/bin/env python3
"""Render a deck folder to PDF.

    python3 render.py <deck-folder>

Reads deck.json for what goes in, template.html for the design, text.md for
the words, theme.json for the page geometry. Writes build/NR_Deck.pdf and a
dated copy beside the deck.
"""

import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deckcore import (Deck, key_for, load_dims, fit_rows, band_height,  # noqa: E402
                      row_height, justify)
import twin  # noqa: E402
from text_io import parse_markdown, inject  # noqa: E402

CHROMES = [
    Path.home() / ".cache/puppeteer/chrome-headless-shell/mac_arm-148.0.7778.97/"
    "chrome-headless-shell-mac-arm64/chrome-headless-shell",
    Path.home() / "Library/Caches/ms-playwright/chromium_headless_shell-1234/"
    "chrome-headless-shell-mac-arm64/chrome-headless-shell",
    Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
]



# ---------------------------------------------------------------------------
# **A glow must be a filter in print.**  Chrome's PDF writer cannot put a
# blurred `text-shadow` into the file, and macOS — Preview, Quick Look, the
# reader he actually opens the PDF in — draws what it does write as the
# shadow's bounding box, filled.  Every neon title in the Call Her Back bible
# came out as stacked rectangles of red and amber, and it was never caught
# because poppler (`pdftoppm`) draws the same file as a perfectly good glow.
#
# The portal's press has done this since 2026-09-07 (`glowsForPrint` in
# hub/src/press.js).  The Mac's own print never did, so the PDF sitting in a
# deck folder did not match the one the portal made.  This is that same
# transform, kept deliberately identical: at most two layers survive — the
# tightest and the widest — and anything blurred wider than WIDEST_BLUR is
# dropped, because a 60px blur is a page of pixels to rasterise for a halo
# nobody can see.  Done in the pipeline, not in any deck's design.
WIDEST_BLUR = 30
PER_UNIT = {"px": 1, "in": 96, "pt": 96 / 72, "pc": 16,
            "cm": 37.8, "mm": 3.78, "em": 16, "rem": 16}


def split_top(value, sep=","):
    """Split on `sep`, but not inside brackets — an `rgba(1, 2, 3, .4)` is one
    thing, not four."""
    out, depth, cur = [], 0, ""
    for ch in value:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch == sep and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [o for o in out if o.strip()]


def blur_of(layer):
    """A shadow layer's blur in pixels: the third length in it, colours removed
    first so a hex or an `rgba()` cannot be read as a number."""
    bare = re.sub(r"(?:rgba?|hsla?|var|color|calc)\([^)]*\)", " ", layer, flags=re.I)
    bare = re.sub(r"#[0-9a-f]{3,8}\b", " ", bare, flags=re.I)
    lengths = re.findall(r"-?\d*\.?\d+(?:px|in|pt|pc|cm|mm|r?em)?", bare, flags=re.I)
    if len(lengths) < 3:
        return 0.0
    third = lengths[2]
    unit = (re.findall(r"[a-z]+$", third, flags=re.I) or [""])[0].lower()
    return abs(float(re.sub(r"[a-z]+$", "", third, flags=re.I))) * PER_UNIT.get(unit, 1)


def glows_for_print(css):
    def one(m):
        value, end = m.group(1), m.group(2)
        if value.strip().lower() == "none":
            return m.group(0)
        layers = [(l, blur_of(l)) for l in split_top(value)]
        layers = [l for l in layers if l[1] <= WIDEST_BLUR]
        if not layers:
            return end                                  # only vast blurs: drop it
        layers.sort(key=lambda l: l[1])
        keep = [layers[0], layers[-1]] if len(layers) > 2 else layers
        return "filter:" + " ".join(f"drop-shadow({l.strip()})" for l, _ in keep) + end
    return re.sub(r"text-shadow\s*:\s*([^;}]+)([;}])", one, css, flags=re.I)


def python_with_pypdf():
    """The launcher runs the system python, which has no pypdf. Find one that
    does rather than failing at the last step of a long build."""
    import shutil
    cands = [sys.executable, "/usr/local/bin/python3", "/opt/homebrew/bin/python3",
             "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
             shutil.which("python3") or ""]
    for c in cands:
        if c and Path(c).exists():
            r = subprocess.run([c, "-c", "import pypdf"], capture_output=True)
            if r.returncode == 0:
                return c
    return None


def dims_of(path):
    out = subprocess.run(["identify", "-format", "%w %h", str(path)],
                         capture_output=True, text=True).stdout.split()
    return (int(out[0]), int(out[1])) if len(out) == 2 else (16, 9)


def as_ratio(said):
    """`"16/9"`, `"4:3"` or a plain number, as a width over a height."""
    if not said:
        return 0.0
    if isinstance(said, (int, float)):
        return float(said) or 0.0
    text = str(said).strip()
    m = re.match(r"^([\d.]+)\s*[/:x]\s*([\d.]+)$", text)
    try:
        if m:
            w, h = float(m.group(1)), float(m.group(2))
            return w / h if h else 0.0
        return float(text)
    except ValueError:
        return 0.0


def grid_ratios(deck):
    """The shape a group asked its frames to be cropped to, per picture.

    **His arrangement is where this lives, and the press had never read it.**
    A group that names a `ratio` is a contact grid — even cells, every one the
    same shape — and `publish.py` has drawn it that way on the website since
    2026-09-06. Nothing carried it to paper: this program reads `deck.json`,
    which holds rows and no ratios, so one group came out a tidy grid on the
    portal and a ragged row of true shapes on the sheet.

    That is **not** a difference between the two media. `decks/PRINT-AND-WEB.md`
    is the list of what is, and the note under rule 8 names this exact case: how
    a group is cropped is his choice about that group, and both sides owe it.

    **Kept per section, not per picture.** A frame may be used in more than one
    part of a bible — nine of his are — and the two places can want it cropped
    differently, or one not at all. Keyed by picture alone, whichever group was
    read last would decide, and a frame would come back cropped in a section
    that never asked for it.
    """
    try:
        arr = json.loads((deck.dir / "arrangement.json").read_text())
    except (OSError, ValueError):
        return {}
    out = {}
    for section in arr.get("sections", []):
        here = out.setdefault(section.get("id", ""), {})
        for g in section.get("groups", []):
            r = as_ratio(g.get("ratio"))
            for k in (g.get("pictures", []) if r else []):
                here[k] = r
    return out


def shapes(row, imgs, grid=None):
    """The aspect of every cell in a row, as it will be *drawn*, and whether
    the row is a grid.

    A row whose frames were all cropped to one shape by the group they came
    from is a contact grid: even cells, every one that shape. Anything else
    keeps its own true shape and the row is ragged by design — including a row
    that straddles two groups, which is nobody's grid.
    """
    grid = grid or {}
    cells = [imgs[k] for k in row if k in imgs]
    want = [grid.get(k, 0.0) for k in row if k in imgs]
    if cells and all(w and abs(w - want[0]) < 1e-9 for w in want):
        return [want[0]] * len(cells), True
    return [c["ar"] for c in cells], False


def prepare_images(deck, paths, max_px, quality):
    """Copy every image the deck uses into build/img/work at print size."""
    out = deck.build_dir / "img" / "work"
    out.mkdir(parents=True, exist_ok=True)
    used = {}
    data = json.loads(deck.deck_file.read_text())
    keys = ([k for p in data.get("projects", []) for pg in p.get("pages", [])
             for r in pg for k in r]
            + list(data.get("cover", []))
            + [k for k in (data.get("slots") or {}).values() if k])
    for n, k in enumerate(dict.fromkeys(keys)):
        src = paths.get(k)
        if not src:
            continue
        dst = out / f"{k}.jpg"
        if not (dst.exists() and dst.stat().st_mtime >= Path(src).stat().st_mtime):
            subprocess.run(["magick", src, "-auto-orient", "-resize",
                            f"{max_px}x{max_px}>", "-quality", str(quality),
                            "-strip", str(dst)], capture_output=True)
        w, h = dims_of(dst)
        used[k] = {"src": f"img/work/{dst.name}", "ar": w / h}
    return used


def fit_page(rows, imgs, page_w, gap, height, max_crop=1.05, grid=None):
    """Work out what it takes for these rows to fill `height` exactly.

    Returns (row_heights_in, width_fraction). A page that comes out a little
    short is widened and trimmed at the sides; one that comes out long is
    narrowed instead, so nothing is ever cropped to make room. A page with too
    little on it to fill is left short rather than blown up.
    """
    live = [[k for k in r if k in imgs] for r in rows]
    live = [r for r in live if r]
    if not live:
        return [], 1.0
    hs = [row_height(shapes(r, imgs, grid)[0], page_w, gap) for r in live]
    avail = height - gap * (len(live) - 1)
    total = sum(hs)
    if total <= 0 or avail <= 0:
        return hs, 1.0
    ratio = avail / total
    if ratio < 1:                       # too tall: narrow it, crop nothing
        return [h * ratio for h in hs], ratio
    if ratio <= max_crop:               # nearly there: widen and trim the sides
        return [h * ratio for h in hs], 1.0
    return hs, 1.0                      # not enough to fill; leave it short


def rows_html(rows, imgs, heights=None, widths=1.0, cls="rw", grid=None):
    out = []
    n = 0
    for r in rows:
        cells = [imgs[k] for k in r if k in imgs]
        if not cells:
            continue
        ars, even = shapes(r, imgs, grid)
        if even:
            # **A grid, not a row of true shapes.** Equal columns, and every
            # frame cropped to fill its cell. Written as inline style rather
            # than a class on purpose: no deck's `template.html` has a rule for
            # this, and a design that has never heard of it must not draw the
            # row broken. The arithmetic works out so nothing is squeezed — a
            # column is (page − gaps) / k wide and the row is that over the
            # ratio tall, so a cell is already the shape it is cropped to.
            cols = f"repeat({len(cells)},minmax(0,1fr))"
            fill = ("width:100%;height:100%;object-fit:cover" if heights else
                    f"width:100%;aspect-ratio:{ars[0]:.4f};object-fit:cover")
            inner = "".join(f'<img src="{c["src"]}" style="{fill}">' for c in cells)
        else:
            cols = " ".join(f'{c["ar"]:.4f}fr' for c in cells)
            inner = "".join(f'<img src="{c["src"]}">' for c in cells)
        style = f"grid-template-columns:{cols}"
        if heights:
            style += f";height:{heights[n]:.4f}in"
        if widths < 0.999:
            style += f";width:{widths * 100:.2f}%"
        out.append(f'<div class="{cls}" style="{style}">{inner}</div>')
        n += 1
    return "".join(out)


def esc(s):
    return (s or "").replace("&", "&amp;").replace("<", "&lt;")


def note_lines(note, per_line=78):
    return 0 if not note else max(1, -(-len(note) // per_line))


def title_size(title, base=46):
    n = len(title or "")
    if n <= 32:
        return base
    if n <= 44:
        return int(base * 0.78)
    return int(base * 0.64)


HEAD_RE = re.compile(r"<!--HEAD:([a-z_]+):([\d.]+)-->(.*?)<!--/HEAD-->", re.S)


def pull_heads(tpl):
    """Take the per-group header blocks out of a template.

    **A page of words and then a page of its pictures leaves a lot of paper
    empty.** His instruction, 2026-09-05: *"for any section with a small amount
    of text and images it should all go on the same page. no need to leave
    blank space"*. So a template may hand a group a header — the claim those
    pictures belong to — and say how many inches to keep for it:

        <!--HEAD:lighting_b:2.4-->...<!--/HEAD-->

    The block is lifted out before the sections are split, printed above the
    group's first page of images, and its budget taken off that page. It keeps
    its `data-t` attributes, so the words still come from text.md like every
    other string in the deck.
    """
    heads = {}
    def take(m):
        heads[m.group(1)] = (m.group(3), float(m.group(2)))
        return ""
    return heads, HEAD_RE.sub(take, tpl)


def build_projects(deck, data, imgs, notes, heads=None, at=None, grids=None):
    """Reference pages. The rows are whatever the editor stored; all that is
    decided here is the size that makes them land exactly on the page."""
    grid = deck.theme["grid"]
    line = float(grid.get("note_line_in", 0.4431))
    base = int(grid.get("note_lines_baseline", 3))
    content_w = deck.page_w - 2 * deck.gap
    frames_foot = deck.theme.get("frames_foot", "Selected work")
    html = []
    # **Every other section, not every picture page.** Tinting all of them
    # turned a red book into a black one — eight sheets in ten — which is the
    # same fault the other way round. Alternating by section keeps the field as
    # the book's colour and lets the dark arrive as a change of air.
    shown = 0
    for p in data.get("projects", []):
        pages = [pg for pg in p.get("pages", []) if any(r for r in pg)]
        if not pages:
            continue
        # **Counted from the deck, not from this call.** Each `__p_<slug>__`
        # marker builds one group on its own, so a counter local to the call
        # restarts at nought every time and every section came out the same
        # colour. `at` carries the group's place in the whole deck.
        alt = ((at if at is not None else shown) % 2) == 1
        shown += 1
        note = notes.get(p["slug"], "")
        first_h = deck.first_budget + (base - note_lines(note)) * line
        for i, pg in enumerate(pages):
            if i == 0:
                own = (heads or {}).get(p.get("slug"))
                if own:
                    head, budget = own[0], first_h - own[1]
                else:
                    head = (f'<div class="phead">'
                            f'<div class="ptitle" style="font-size:'
                            f'{title_size(p.get("title"))}pt">{esc(p.get("title"))}</div>'
                            f'<div class="pcred">{esc(p.get("credit"))}</div></div>')
                    budget = first_h
                tail = f'<p class="pnote">{note}</p>' if note else ""
            else:
                head = (f'<div class="phead cont"><div class="pcont">{esc(p.get("title"))}'
                        f' <span>continued</span></div></div>')
                tail = ""
                budget = deck.cont_budget
            grid = (grids or {}).get(p["slug"], {})
            hs, w = fit_page(pg, imgs, content_w, deck.gap, budget, grid=grid)
            used = sum(hs) + deck.gap * max(0, len(hs) - 1)
            body = rows_html(pg, imgs, hs, w, grid=grid)
            if used < budget - 0.05 and tail:
                # Not enough on this page to fill it. Keep the caption with its
                # images and centre the pair, rather than stranding it at the
                # bottom of an empty page.
                body += tail
                tail = ""
            # **Not every page the same colour.** His note, 2026-09-05: *"for
            # the PDF, not every page needs to be red. We should offset with
            # black sometimes too."* A deck that names `alt_pages` in its theme
            # gets its picture pages on the other ground, so the book alternates
            # — words on the field, frames on the dark — instead of running one
            # colour for twenty sheets.
            #
            # Written as an inline `background-color` on purpose: `.page` sets
            # `background` as a shorthand with a noise texture in it, and the
            # longhand overrides only the colour, so the texture survives. It
            # also means no deck's template has to be edited to gain this.
            tint = deck.theme.get("alt_pages") if alt else None
            paint = f' style="background-color:{tint}"' if tint else ""
            html.append(
                f'<div class="page"{paint}>\n  {head}\n'
                f'  <div class="shots" style="height:{budget:.4f}in">'
                f'{body}</div>\n  {tail}\n'
                f'  <div class="foot"><span>{esc(frames_foot)}</span>'
                f'<span class="r">00</span></div>\n</div>\n')
    return "\n".join(html)


def build_collage(deck, data, imgs):
    keys = [k for k in data.get("cover", []) if k in imgs]
    if not keys:
        return ""
    content_w = deck.page_w - 2 * deck.gap
    ars = [imgs[k]["ar"] for k in keys]
    parts, hs, w, s, filled, _ = justify(
        ars, content_w, deck.gap, deck.full_budget,
        max_per_row=int(deck.theme["grid"].get("collage_max_per_row", 5)))
    rows, i = [], 0
    for n in parts:
        rows.append(keys[i:i + n])
        i += n
    return ('<div class="page">\n  <div class="mosaic">'
            + rows_html(rows, imgs, hs, w, cls="rw") + '</div>\n'
            '  <div class="foot"><span>x</span><span class="r">00</span></div>\n</div>\n')


def fill_slots(html, data, imgs):
    """Template images marked data-slot="name" can be swapped in the editor.
    deck.json["slots"] maps a slot name to an image key; anything unassigned
    keeps whatever the template shipped with."""
    slots = data.get("slots") or {}

    def rep(m):
        tag, name = m.group(0), m.group(1)
        key = slots.get(name)
        if not key or key not in imgs:
            return tag
        return re.sub(r'src="[^"]*"', f'src="{imgs[key]["src"]}"', tag)

    return re.sub(r'<img[^>]*data-slot="([^"]+)"[^>]*>', rep, html)


def split_sections(tpl):
    first = tpl.index("<!--SECTION:")
    head, rest = tpl[:first], tpl[first:]
    at = rest.rindex("</body>")
    body, tail = rest[:at], rest[at:]
    parts = re.split(r"<!--SECTION:([a-z_]+)-->", body)
    return head, {parts[i]: parts[i + 1] for i in range(1, len(parts), 2)}, tail


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: render.py <deck-folder> [--html]")
    html_only = "--html" in sys.argv
    deck = Deck(sys.argv[1])
    # **A document that is already assembled.** The press hands over the sheets
    # the editor published, which are the ones he arranged and looked at; there
    # is nothing left here to decide, so everything below is skipped and only
    # the printing happens. Without `--from` this behaves exactly as it did.
    if "--from" in sys.argv:
        given = Path(sys.argv[sys.argv.index("--from") + 1])
        return print_document(deck, given.read_text())
    data = json.loads(deck.deck_file.read_text())
    groups, paths, labels = deck.scan()

    out = deck.theme.get("output", {})
    imgs = prepare_images(deck, paths, out.get("max_px", 1250), out.get("quality", 80))

    heads, tpl = pull_heads(deck.template.read_text())
    head, sections, tail = split_sections(tpl)
    notes = deck.theme.get("project_notes", {})
    grids = grid_ratios(deck)
    sections["__projects__"] = build_projects(deck, data, imgs, notes, heads,
                                              grids=grids)
    # **A template may also place one group on its own.** `__projects__` renders
    # every group in one run, which is right for a portfolio deck — the work,
    # back to back — and wrong for anything that alternates. A visual bible is
    # a section of words, then that section's frames, then the next: with only
    # the one marker every word in the deck lands before every picture in it.
    #
    # His instruction, 2026-09-05: *"deck editor needs to be able to be even
    # more flexible"*. So each group is also offered under a marker of its own,
    # `__p_<slug>__`, and a template that does not use them is unaffected.
    for n, one in enumerate(data.get("projects", [])):
        slug = re.sub(r"[^a-z_]+", "_", str(one.get("slug", "")).lower())
        if slug:
            sections[f"__p_{slug}__"] = build_projects(
                deck, {**data, "projects": [one]}, imgs, notes, heads, at=n,
                grids=grids)
    collage = build_collage(deck, data, imgs)
    if collage:
        sections["collage"] = "\n" + collage + "\n"

    for sid in sections:
        sections[sid] = fill_slots(sections[sid], data, imgs)

    if deck.text_md.exists():
        values = parse_markdown(deck.text_md.read_text())
        for sid in sections:
            sections[sid] = inject(sections[sid], values)

    order = [s["id"] for s in data.get("sections", []) if s.get("on", True)]
    if not order:
        order = list(sections)
    doc = head + "".join(sections.get(i, "") for i in order) + tail

    n = [1]

    def bump(_m):
        n[0] += 1
        return f'<span class="r">{n[0]:02d}</span>'

    doc = re.sub(r'<span class="r">\d+</span>', bump, doc)

    # Progress along the foot of each page, the way the reference deck does it:
    # the strip fills as you move through the deck.
    total = doc.count('<div class="page')
    if total:
        idx = [0]

        def prog(m):
            idx[0] += 1
            pct = idx[0] / total * 100
            tag = m.group(0)
            if "style=" in tag:
                return tag.replace('style="', f'style="--prog:{pct:.1f}%;', 1)
            return tag[:-1] + f' style="--prog:{pct:.1f}%">'

        doc = re.sub(r'<div class="page[^"]*"[^>]*>', prog, doc)
    (deck.build_dir / "deck.html").write_text(glows_for_print(doc))
    pages = doc.count('<div class="page')
    print(f"assembled {pages} pages: {', '.join(order)}")

    for name in ("assets",):
        src = deck.dir / name
        if src.is_dir():
            dst = deck.build_dir / name
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)

    if html_only:
        # For looking at and measuring, so it keeps the shadows as the design
        # wrote them; only what goes to the press is turned into filters.
        (deck.build_dir / "deck.html").write_text(doc)
        print("html only")
        return deck.build_dir / "deck.html"

    chrome = next((c for c in CHROMES if c.exists()), None)
    if not chrome:
        raise SystemExit("No headless Chrome found.")
    subprocess.run([str(chrome), "--headless", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", "--print-to-pdf=content.pdf",
                    "deck.html"], cwd=deck.build_dir, check=True, capture_output=True)

    bg = deck.build_dir / "bg.pdf"
    if deck.theme.get("underlay", True):
        make_underlay(deck, chrome, bg)
        py = python_with_pypdf()
        if not py:
            raise SystemExit("No python with pypdf installed; cannot merge the "
                             "background underlay.")
        subprocess.run([py, str(Path(__file__).parent / "merge.py"),
                        "content.pdf", "NR_Deck.pdf", str(bg)],
                       cwd=deck.build_dir, check=True)
    else:
        shutil.copy(deck.build_dir / "content.pdf", deck.build_dir / "NR_Deck.pdf")

    stamp = time.strftime("%Y-%m-%d")
    final = deck.dir / f"{deck.theme.get('file_stem', __import__('registry').deck_name(deck.dir))}_{stamp}.pdf"
    shutil.copy(deck.build_dir / "NR_Deck.pdf", final)
    print(f"wrote {final}")
    # In a project's `1-creative/decks/<deck>/z-source`, the current PDF also
    # goes up to the deck's home folder and the older ones to its z-archive.
    try:
        import registry
        up = registry.file_pdf_home(final)
        if up:
            print(f"filed {up}")
    except OSError as e:
        print(f"(could not file the PDF at the deck's top: {e})")
    return final


def print_document(deck, doc):
    """Print an assembled document, and paint its paper underneath."""
    (deck.build_dir / "deck.html").write_text(glows_for_print(doc))
    for name in ("assets",):
        src = deck.dir / name
        if src.is_dir():
            dst = deck.build_dir / name
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
    chrome = next((c for c in CHROMES if c.exists()), None)
    if not chrome:
        raise SystemExit("No headless Chrome found.")
    subprocess.run([str(chrome), "--headless", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", "--print-to-pdf=content.pdf",
                    "deck.html"], cwd=deck.build_dir, check=True, capture_output=True)
    bg = deck.build_dir / "bg.pdf"
    if deck.theme.get("underlay", True):
        make_underlay(deck, chrome, bg)
        py = python_with_pypdf()
        if not py:
            raise SystemExit("No python with pypdf installed; cannot merge the "
                             "background underlay.")
        subprocess.run([py, str(Path(__file__).parent / "merge.py"),
                        "content.pdf", "NR_Deck.pdf", str(bg)],
                       cwd=deck.build_dir, check=True)
    else:
        shutil.copy(deck.build_dir / "content.pdf", deck.build_dir / "NR_Deck.pdf")
    stamp = time.strftime("%Y-%m-%d")
    final = deck.dir / f"{deck.theme.get('file_stem', __import__('registry').deck_name(deck.dir))}_{stamp}.pdf"
    shutil.copy(deck.build_dir / "NR_Deck.pdf", final)
    print(f"wrote {final}")
    # In a project's `1-creative/decks/<deck>/z-source`, the current PDF also
    # goes up to the deck's home folder and the older ones to its z-archive.
    try:
        import registry
        up = registry.file_pdf_home(final)
        if up:
            print(f"filed {up}")
    except OSError as e:
        print(f"(could not file the PDF at the deck's top: {e})")
    say_drift(deck)
    return final


def say_drift(deck):
    """Say if the two designs have stopped saying the same thing.

    **Said, never enforced.** A printed deck is often wanted before its words
    are finished, and refusing to print because a paragraph has not reached the
    web design yet would be this program deciding his priorities for him. So it
    prints, and then says — which is the whole difference between a warning and
    a gate. `twin.py` on its own is the one that exits non-zero, for anything
    that wants to be told properly.
    """
    try:
        faults, wrong, _notes = twin.check(deck.dir)
    except Exception:
        return
    if faults:
        print(f"\n{faults} things the print design and the web design "
              f"disagree about:")
        print("\n".join(wrong))
        print("  (decks/PRINT-AND-WEB.md — rule 1: they may be cut "
              "differently, never say different things)")


def make_underlay(deck, chrome, bg):
    """A full-bleed background page, merged under every content page. Chromium
    will not print a body background on its own."""
    colour = deck.theme.get("colors", {}).get("paper", "#ffffff")
    html = deck.build_dir / "bg.html"
    html.write_text(
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>"
        f"@page{{size:{deck.theme['page'].get('css_size','letter')};margin:0}}"
        "*{margin:0;padding:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}"
        f".pg{{width:{deck.page_w}in;height:{deck.page_h}in;background:{colour}}}"
        "</style></head><body><div class='pg'></div></body></html>")
    subprocess.run([str(chrome), "--headless", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer", f"--print-to-pdf={bg.name}", "bg.html"],
                   cwd=deck.build_dir, check=True, capture_output=True)


if __name__ == "__main__":
    main()
