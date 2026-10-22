"""Seed a local bucket with a film that carries one deck, so the editor and the
live page can be measured against each other."""
import json, os, struct, sys, zlib
from pathlib import Path

OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)

def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b""))

# Twelve stills of three different shapes, so a row's true-ratio widths differ.
SHAPES = [(240, 100), (160, 100), (200, 100)]
COLOURS = [(200, 70, 70), (70, 160, 200), (200, 180, 70), (120, 200, 120),
           (180, 110, 200), (230, 140, 90), (90, 120, 220), (200, 200, 200),
           (150, 90, 60), (60, 150, 140), (210, 90, 150), (110, 110, 110)]
pics, names = {}, []
for i, colour in enumerate(COLOURS):
    w, h = SHAPES[i % 3]
    name = f"{i:032x}.png"
    png(OUT / name, w, h, colour)
    names.append(name)
    pics[f"k{i}"] = {"name": name, "ar": round(w / h, 4)}

sections = [
    {"id": "opening", "title": "Opening", "on": True, "groups": [
        {"emphasis": "hero", "pictures": ["k0"]},
        {"emphasis": "normal", "pictures": ["k1", "k2", "k3", "k4", "k5"]},
    ]},
    {"id": "worlds", "title": "Worlds", "on": True, "groups": [
        {"emphasis": "quiet", "pictures": ["k6", "k7", "k8", "k9"], "ratio": "4/3"},
        {"emphasis": "large", "pictures": ["k10", "k11"]},
    ]},
]

record = {
    "version": 1, "name": "Look Book", "sections": sections, "pictures": pics,
    "words": {"cover.title1": "Look Book", "opening.head1": "Opening",
              "opening.b1": "The first ten minutes.", "worlds.head1": "Worlds"},
    "crop": {}, "updated": "2026-09-06T00:00:00Z", "printed": "2026-09-06T00:00:00Z",
}
(OUT / "deck.json").write_text(json.dumps(record))

# **A paper design, the way `publish.py` pushes one.** The print stylesheet, the
# page geometry, and each section's own block of words — enough for the editor
# to draw the sheets exactly as they print, and nothing about where the pictures
# land, which is his.
PAPER_CSS = """.page{width:8.5in;height:11in;position:relative;overflow:hidden;
  page-break-after:always;background:#161214;color:#EFE1D6;padding:.5in;
  font:14px/1.4 system-ui,sans-serif;box-sizing:border-box}
.page.red{background:#4D0812}
.page *{box-sizing:border-box}
.dhead .kk{font-size:9px;letter-spacing:.14em;text-transform:uppercase;color:#C9A5A2}
.dhead h2{font:300 34px/1 Georgia,serif;color:#F2C14E;margin:4px 0 10px}
.dhead p{margin:0 0 8px;max-width:60%}
.phead.cont .pcont{font-size:11px;color:#C9A5A2;margin-bottom:10px}
.shots{display:flex;flex-direction:column;justify-content:center;gap:.11in;margin:0}
.shots .rw{display:grid;gap:.11in;margin:0 auto}
.shots .rw img{width:100%;height:100%;object-fit:cover;display:block}
.foot{position:absolute;left:.5in;right:.5in;bottom:.32in;display:flex;
  justify-content:space-between;font-size:9px;letter-spacing:.12em;
  text-transform:uppercase;color:#C9A5A2}"""

paper = {
    "css": PAPER_CSS,
    "theme": {"w": 8.5, "h": 11, "gap": 0.11, "first": 9.4, "cont": 9.9},
    "foot": "Look Book",
    "alt": "#161214",
    # **Both shapes a block comes in.** Since 2026-09-07 `publish.py` sends a
    # block as `{html, cls, style}` — the words and the dress of the sheet that
    # held them — so the editor can draw a red sheet red. A kit pushed before
    # then is a bare string, and the editor has to take that too.
    "blocks": {
        "opening": {"html": '<div class="kk">Call Her Back</div>'
                            '<h2 data-t="opening.head1">Opening</h2>'
                            '<p data-t="opening.b1">The first ten minutes.</p>',
                    "cls": "red", "style": ""},
        "worlds": '<div class="kk">Call Her Back</div>'
                  '<h2 data-t="worlds.head1">Worlds</h2>',
    },
    "heads": {
        # A head dresses the first sheet of its pictures the same way a block
        # dresses a sheet of words; the seed says `red` here so that road is
        # driven too.
        "opening": {"inches": 1.6, "cls": "red", "style": "",
                    "html": '<div class="kk">Call Her Back</div>'
                            '<h2 data-t="opening.head1">Opening</h2>'
                            '<p data-t="opening.b1">The first ten minutes.</p>'},
    },
}
(OUT / "paper.json").write_text(json.dumps(paper))


DESIGN = """.deckweb{color:var(--ink,#D9D9D9);font-family:system-ui,sans-serif;font-size:16px;line-height:1.62}
.deckweb *{box-sizing:border-box}
.deckweb .inner{max-width:1180px;margin:0 auto;padding:0 28px}
.deckweb .top{padding:9vh 0 7vh}
.deckweb .top h1{font-size:clamp(34px,6vw,74px);font-weight:800;margin:0 0 12px}
.deckweb .sec{display:flex;align-items:baseline;gap:10px;margin:0 0 6px;padding-top:8vh}
.deckweb .sec h2{font-size:clamp(20px,2.3vw,28px);font-weight:700;margin:0}
.deckweb .rule{height:1px;background:rgba(255,255,255,.10);margin:0 0 24px}
.deckweb p{max-width:64ch;margin:0 0 14px}
.deckweb .frames{margin:24px 0 0}
.deckweb .frow{display:flex;gap:6px;margin:0 0 6px}
.deckweb .frow figure{margin:0;min-width:0}
.deckweb .frow img{width:100%;height:100%;object-fit:cover;display:block;background:#141414}"""

def frames(section):
    rows = []
    for group in section["groups"]:
        keys = group["pictures"]
        ratio = group.get("ratio")
        total = sum(pics[k]["ar"] for k in keys)
        cells = []
        for k in keys:
            wide = "" if ratio else f' style="width:{pics[k]["ar"] / total * 100:.3f}%"'
            cells.append(f'<figure data-key="{k}"{wide}><img src="pic/{pics[k]["name"]}" alt="" loading="lazy"></figure>')
        if ratio:
            rows.append(f'<div class="frow even" style="--cells:{len(cells)};--cell:{ratio}">{"".join(cells)}</div>')
        else:
            solo = " solo" if len(cells) == 1 else ""
            rows.append(f'<div class="frow{solo}" style="--ar:{total:.4f};width:100.00%">{"".join(cells)}</div>')
    return f'<div class="frames" data-section="{section["id"]}">{"".join(rows)}</div>'

body = ['<div class="deckweb"><div class="inner">',
        '<header class="top"><h1 data-t="cover.title1">Look Book</h1></header>']
for s in sections:
    body.append(f'<div class="sec"><span class="arrow">&rsaquo;</span>'
                f'<h2 data-t="{s["id"]}.head1">{s["title"]}</h2></div><div class="rule"></div>')
    if s["id"] == "opening":
        body.append('<p data-t="opening.b1">The first ten minutes.</p>')
    body.append(frames(s))
body.append('</div></div>')
(OUT / "page.html").write_text(f"<style>{DESIGN}</style>\n" + "".join(body))

front = {
    "project": "01a02852ebb00198e46a252100000000", "title": "Call Her Back",
    "sections": [{"slug": "lookbook", "name": "Look Book", "title": "", "by": "deck"}],
    "documents": [{"name": "Look Book", "kind": "lookbook", "file": "%s.pdf" % ("ab" * 16), "bytes": 1000}],
    "crew": [], "updated": "2026-09-06T00:00:00Z",
}
(OUT / "front.json").write_text(json.dumps(front))

pdf = (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
       b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
       b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\n"
       b"trailer<</Root 1 0 R>>\n%%EOF\n")
(OUT / ("%s.pdf" % ("ab" * 16))).write_bytes(pdf)
(OUT / "names.json").write_text(json.dumps(names))
print(f"seeded {len(names)} pictures into {OUT}")
