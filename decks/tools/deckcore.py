#!/usr/bin/env python3
"""Shared core for the deck builder.

A deck is a folder. Everything about it lives there:

    theme.json      page size, grid geometry. The design's measurements.
    sources.json    where images come from, and how they are labelled
    template.html   the design, marked with <!--SECTION:id--> and data-t keys
    text.md         the words, keyed to the data-t attributes
    deck.json       what was chosen and arranged, written by the editor
    assets/         fonts, logo, any images the template refers to directly
    build/          render output

Nothing here knows about any particular deck. Point it at a folder and it
reads that folder's config.
"""

import hashlib
import re
import json
import subprocess
from pathlib import Path

CACHE = Path.home() / "Library/Caches/nr-deck-builder"
THUMBS = CACHE / "thumbs"
DIMS_FILE = CACHE / "dims.json"
THUMBS.mkdir(parents=True, exist_ok=True)


_Z_SOURCE = re.compile(r"/1-creative/decks/([^/]+)/z-source(?=/|$)")


def key_for(path) -> str:
    """A picture's key: sha1 of its absolute path, first 16 hex.

    **Keys must not change when a deck folder moves.** The portal's records,
    `arrangement.json` and `deck.json` all name pictures by this key. On
    2026-10-15 the project decks moved from `1-creative/<deck>/` to
    `1-creative/decks/<deck>/z-source/`; to keep every existing key valid, a
    path inside `z-source` is hashed as the old path it used to have.
    """
    return hashlib.sha1(_Z_SOURCE.sub(r"/1-creative/\1", str(path)).encode()).hexdigest()[:16]


# ---------------------------------------------------------------- config ----

DEFAULT_THEME = {
    "name": "untitled",
    "page": {"width_in": 8.5, "height_in": 11.0, "css_size": "letter"},
    "grid": {
        "gap_in": 0.07,
        # How much image height a project's first page can hold, and how much
        # a continuation page can. Set by how much furniture the template puts
        # on each (title block, caption, footer).
        "first_budget_in": 7.35,
        "cont_budget_in": 8.75,
        # Full-page budget for an untitled grid such as an opening collage.
        "full_budget_in": 10.35,
    },
}


class Deck:
    def __init__(self, folder):
        self.dir = Path(folder).expanduser().resolve()
        if not self.dir.is_dir():
            raise SystemExit(f"No such deck folder: {self.dir}")
        self.theme = self._read("theme.json", DEFAULT_THEME)
        self.sources = self._read("sources.json", {"pools": []})
        self.deck_file = self.dir / "deck.json"
        self.template = self.dir / "template.html"
        self.text_md = self.dir / "text.md"
        self.build_dir = self.dir / "build"
        self.assets = self.dir / "assets"
        self.history = self.dir / ".history"
        self.history.mkdir(exist_ok=True)
        self.build_dir.mkdir(exist_ok=True)

    def _read(self, name, default):
        p = self.dir / name
        if not p.exists():
            return json.loads(json.dumps(default))
        merged = json.loads(json.dumps(default))
        got = json.loads(p.read_text())
        for k, v in got.items():
            if isinstance(v, dict) and isinstance(merged.get(k), dict):
                merged[k].update(v)
            else:
                merged[k] = v
        return merged

    # geometry the layout maths needs
    @property
    def page_w(self):
        return float(self.theme["page"]["width_in"])

    @property
    def page_h(self):
        return float(self.theme["page"]["height_in"])

    @property
    def gap(self):
        return float(self.theme["grid"]["gap_in"])

    @property
    def first_budget(self):
        return float(self.theme["grid"]["first_budget_in"])

    @property
    def cont_budget(self):
        return float(self.theme["grid"]["cont_budget_in"])

    @property
    def full_budget(self):
        return float(self.theme["grid"]["full_budget_in"])

    # ------------------------------------------------------------ images ----

    def scan(self):
        """Return (groups, paths, labels).

        groups: group-id -> [image paths]      what the editor offers to add
        paths:  key -> path                    how the build resolves a key
        labels: group-id -> {title, credit}
        """
        groups, labels = {}, {}
        for pool in self.sources.get("pools", []):
            root = Path(pool["root"]).expanduser()
            if not root.is_dir():
                continue
            file_glob = pool.get("file_glob", "*.jpg")
            exclude = pool.get("exclude", [])
            titles = pool.get("titles", {})
            credits = pool.get("credits", {})
            include = pool.get("include")
            prefer_unmatted = pool.get("prefer_unmatted", False)

            # Images are sometimes grouped by folder, sometimes by a prefix in
            # the filename (an export that dumps everything into one folder).
            prefixes = pool.get("group_prefixes")
            if prefixes:
                import re
                found = [str(f) for f in sorted(root.rglob(file_glob))
                         if not any(x in str(f) for x in exclude)]
                buckets = {}
                for f in found:
                    stem = re.sub(r"^\d+-", "", Path(f).name)
                    gid = next((g for g in prefixes if stem.startswith(g)), "other")
                    buckets.setdefault(gid, []).append(f)
                for gid, files in buckets.items():
                    if include is not None and gid not in include:
                        continue
                    groups[gid] = files
                    labels[gid] = {"title": titles.get(gid, gid.replace("-", " ").title()),
                                   "credit": credits.get(gid, "")}
                continue

            if pool.get("group_glob"):
                dirs = sorted(d for d in root.glob(pool["group_glob"]) if d.is_dir())
            else:
                dirs = [root]

            for d in dirs:
                gid = d.name
                for suf in pool.get("strip_suffix", []):
                    if gid.endswith(suf):
                        gid = gid[: -len(suf)]
                if include is not None and gid not in include:
                    continue
                found = [str(p) for p in sorted(d.rglob(file_glob))
                         if not any(x in str(p) for x in exclude)]
                if prefer_unmatted:
                    plain = {s for s in found if "matted" not in s}
                    found = [s for s in found
                             if "matted" not in s
                             or s.replace("-showcase-stills-matted.webp",
                                          "-showcase-stills.webp")
                                 .replace("/matted/", "/") not in plain]
                if not found:
                    continue
                groups[gid] = found
                labels[gid] = {
                    "title": titles.get(gid, gid.replace("-", " ").title()),
                    "credit": credits.get(gid, ""),
                }
        paths = {key_for(s): s for v in groups.values() for s in v}
        return groups, paths, labels


# ---------------------------------------------------------------- thumbs ----

def jpeg_size(path):
    """Width/height from a JPEG header, so Pillow is not a dependency."""
    try:
        with open(path, "rb") as f:
            if f.read(2) != b"\xff\xd8":
                return None
            while True:
                b = f.read(1)
                if not b:
                    return None
                if b != b"\xff":
                    continue
                while b == b"\xff":
                    b = f.read(1)
                    if not b:
                        return None
                m = b[0]
                if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
                    continue
                head = f.read(2)
                if len(head) < 2:
                    return None
                ln = int.from_bytes(head, "big")
                if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
                    body = f.read(5)
                    if len(body) < 5:
                        return None
                    return (int.from_bytes(body[3:5], "big"),
                            int.from_bytes(body[1:3], "big"))
                f.seek(ln - 2, 1)
    except OSError:
        return None


def ensure_thumb(src):
    out = THUMBS / f"{key_for(src)}.jpg"
    if not out.exists():
        subprocess.run(["magick", str(src), "-auto-orient", "-resize",
                        "420x420>", "-quality", "72", str(out)],
                       capture_output=True)
    return out


def load_dims(paths):
    """Aspect ratios for every image, cached. Without these the editor grid
    collapses before the thumbnails arrive."""
    try:
        dims = json.loads(DIMS_FILE.read_text())
    except Exception:
        dims = {}
    missing = [(k, s) for k, s in paths.items() if k not in dims]
    if missing:
        print(f"Measuring {len(missing)} thumbnails...")
        for k, src in missing:
            t = ensure_thumb(src)
            wh = jpeg_size(t) if t.exists() else None
            dims[k] = list(wh) if wh else [16, 9]
        try:
            DIMS_FILE.write_text(json.dumps(dims))
        except OSError:
            pass
    return dims


# ------------------------------------------------------------ row layout ----

def band_height(page_w, gap, per_row, ar):
    return ((page_w - gap * (per_row - 1)) / per_row) / ar


def true_height(rows, ars, page_w, gap):
    """Real height of a set of rows: each row is as tall as its flattest image."""
    return sum(max(band_height(page_w, gap, len(r), ars.get(k, 1.78)) for k in r) + gap
               for r in rows if r)


def fit_rows(keys, ars, page_w, gap, budget, force_hero=False, max_per_row=3):
    """Split keys into rows of 1-3 filling `budget` as fully as possible
    without exceeding it.

    A row's height depends on how many images share it, so the search is over
    how many 1-up, 2-up and 3-up rows to use. Candidates are then measured
    against the real images rather than an average, because a row of 2.39s and
    a row of 1.78s are not the same height.
    """
    n = len(keys)
    if n == 0:
        return []
    med = sorted(ars.values())[len(ars) // 2] if ars else 1.78
    sizes = tuple(range(1, max_per_row + 1))
    est = {p: band_height(page_w, gap, p, med) + gap for p in sizes}

    # Every way of writing n as a sum of the allowed row sizes.
    cands = []

    def walk(remaining, counts, idx, height):
        if height > budget:
            return
        if remaining == 0:
            if not force_hero or counts.get(1):
                cands.append((height, dict(counts)))
            return
        if idx >= len(sizes):
            return
        p = sizes[idx]
        for k in range(remaining // p + 1):
            counts[p] = k
            walk(remaining - k * p, counts, idx + 1, height + k * est[p])
        counts.pop(p, None)

    walk(n, {}, 0, 0.0)

    def spread(counts):
        used = [p for p in sizes if counts.get(p)]
        return (max(used) - min(used)) if used else 0

    # A grid reads better when its rows are close in size, so try the even
    # candidates first and only widen the search if none of them fit.
    cands.sort(key=lambda c: (spread(c[1]), -c[0]))
    even = [c for c in cands if spread(c[1]) <= 1]
    rest = [c for c in cands if spread(c[1]) > 1]
    even.sort(key=lambda c: -c[0])
    rest.sort(key=lambda c: -c[0])
    cands = even + rest

    def lay(counts):
        plan = []
        for p in sizes:                       # bigger images first
            plan += [p] * counts.get(p, 0)
        rows, i = [], 0
        for p in plan:
            rows.append(keys[i:i + p])
            i += p
        return [r for r in rows if r]

    for _, counts in cands:
        rows = lay(counts)
        if true_height(rows, ars, page_w, gap) <= budget:
            return rows

    # Nothing fits; fall back to the flattest packing available.
    return [keys[i:i + 3] for i in range(0, n, 3)]


# --------------------------------------------------------- justified rows ----
#
# A row always spans the full width, so its height falls out of its images'
# aspect ratios: h = (W - (k-1)g) / sum(aspects). Filling a page exactly is
# therefore a question of which images share a row, not of stretching anything.
# Whatever is left over after the best split is taken up by one scale factor
# applied to the whole column, kept within a few per cent so the crop it costs
# is invisible.


def row_height(ars_row, page_w, gap):
    k = len(ars_row)
    return (page_w - gap * (k - 1)) / sum(ars_row)


def _compositions(n, max_part, max_parts):
    """Every ordered way to write n as a sum of parts 1..max_part."""
    out = []

    def walk(rem, parts):
        if rem == 0:
            out.append(tuple(parts))
            return
        if len(parts) == max_parts:
            return
        for p in range(1, min(max_part, rem) + 1):
            parts.append(p)
            walk(rem - p, parts)
            parts.pop()

    walk(n, [])
    return out


def justify(ars, page_w, gap, height, max_per_row=5, max_rows=6,
            max_crop=1.05, min_width=0.50):
    """Split a run of images into rows that fill `height` exactly.

    Two ways to take up the slack, in order of preference:

    1. If the rows come out a little short, scale them up and let
       `object-fit: cover` trim the sides. Kept to a few per cent, where it
       cannot be seen.
    2. If they come out long, narrow the whole column instead. The images keep
       every pixel; they just sit in from the edges.

    Returns (parts, height_in, width_frac, scale, filled, cost).
    """
    n = len(ars)
    if n == 0:
        return (), [], 1.0, 1.0, False, 0.0
    if n > 16:
        max_rows = 8
    best = short = None
    for parts in _compositions(n, max_per_row, max_rows):
        hs, i = [], 0
        for p in parts:
            hs.append(row_height(ars[i:i + p], page_w, gap))
            i += p
        avail = height - gap * (len(parts) - 1)
        if avail <= 0:
            continue
        total = sum(hs)
        # Rows of roughly equal size read as a grid; a hero beside a row of
        # five reads as an accident.
        even = (max(parts) - min(parts)) * 0.6
        if total >= avail:
            f = avail / total                      # narrow, nothing cropped
            if f >= min_width:
                cost = (1 - f) * 16 + even + 0.2
                cand = (cost, parts, [h * f for h in hs], f, 1.0)
                if best is None or cost < best[0]:
                    best = cand
        else:
            s = avail / total                      # widen, trim the sides
            if s <= max_crop:
                cost = (s - 1) * 12 + even
                cand = (cost, parts, [h * s for h in hs], 1.0, s)
                if best is None or cost < best[0]:
                    best = cand
            else:
                cost = 2.0 + (1 - total / height) * 16 + even
                if short is None or cost < short[0]:
                    short = (cost, parts, hs, 1.0, 1.0)
    if best:
        return best[1], best[2], best[3], best[4], True, best[0]
    if short:
        return short[1], short[2], 1.0, 1.0, False, short[0]
    parts = tuple([max_per_row] * (n // max_per_row)
                  + ([n % max_per_row] if n % max_per_row else []))
    hs, i = [], 0
    for p in parts:
        hs.append(row_height(ars[i:i + p], page_w, gap))
        i += p
    return parts, hs, 1.0, 1.0, False, 12.0


def plan_pages(ars, page_w, gap, first_h, cont_h, min_per_page=4, max_per_page=14):
    """Break an ordered run of images into pages that each fill their page.

    Order is never changed: pages are contiguous slices. All this decides is
    how many go on a page and who shares a row.
    """
    n = len(ars)
    if n == 0:
        return []
    if n <= min_per_page:
        return [(0, n, justify(ars, page_w, gap, first_h))]

    seg_cache, memo = {}, {}

    def seg(i, j, h):
        key = (i, j, round(h, 4))
        if key not in seg_cache:
            seg_cache[key] = justify(ars[i:j], page_w, gap, h)
        return seg_cache[key]

    def solve(i, first):
        key = (i, first)
        if key in memo:
            return memo[key]
        if i == n:
            return (0.0, [])
        h = first_h if first else cont_h
        best = (float("inf"), [])
        for j in range(min(i + min_per_page, n), min(n, i + max_per_page) + 1):
            if 0 < n - j < min_per_page:      # never leave a scrap behind
                continue
            got = seg(i, j, h)
            rest = solve(j, False)
            cost = got[5] + 1.2 + rest[0]     # a page has to earn itself
            if cost < best[0]:
                best = (cost, [(i, j, got)] + rest[1])
        if best[0] == float("inf"):
            got = seg(i, n, h)
            best = (got[5], [(i, n, got)])
        memo[key] = best
        return best

    return solve(0, True)[1]


def flow_pages(rows, ars, page_w, gap, first, cont):
    """Break a flat row list into pages using the print budgets."""
    pages, page, used, budget = [], [], 0.0, first
    for r in rows:
        h = max(band_height(page_w, gap, len(r), ars.get(k, 1.78)) for k in r) + gap
        if used + h > budget and page:
            pages.append(page)
            page, used, budget = [], 0.0, cont
        page.append(r)
        used += h
    if page:
        pages.append(page)
    return pages or [[]]
