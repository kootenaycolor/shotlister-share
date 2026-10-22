#!/usr/bin/env python3
"""Our own pictures for the pack's flat lamps.

His ruling, 2026-09-27, was the pack's pictures untouched. His word,
2026-10-01, on the LiteMat 8 and its kind: "very flat and just feel like
square, add some detail in them so we understand what they are". A pale
grey square on paper reads as nothing, worse once the plan inks it grey.
These few are drawn here instead, at the pack's own size in pixels, so
their place on the plan, their outline and their size do not move:
a dark frame, a lit face with its rows of LEDs, corner hardware, and the
cable box at the back (the picture's top is the lamp's front).

Writes over engine/assets/fso/<id>.png. tools/fso_import.py runs this
after it copies the pack, so a new pack never brings the flat ones back.
Run alone: python3 tools/fso_redraw.py, then python3 tools/fso_outlines.py
"""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "engine/assets/fso")
S = 4  # drawn four times over, then brought down, for clean edges

FRAME = (38, 38, 40, 255)
RIM = (92, 92, 96, 255)
FACE = (248, 245, 236, 255)
SHADE = (226, 221, 207, 255)
LED = (214, 207, 188, 255)
METAL = (178, 180, 184, 255)
BOLT = (60, 60, 64, 255)
AMBER = (232, 150, 52, 255)  # LiteGear's tail
RED = (214, 52, 58, 255)  # Aputure's
CAP = (30, 30, 32, 255)


def canvas(w, h):
    im = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im, w, h, name):
    im.resize((w, h), Image.LANCZOS).save(os.path.join(ASSETS, name + ".png"))


def face(d, x0, y0, x1, y1, r):
    """The lit face: warm white, a touch darker toward its edge."""
    d.rounded_rectangle((x0, y0, x1, y1), r, fill=SHADE)
    k = max(2 * S, round(min(x1 - x0, y1 - y0) * 0.035))
    d.rounded_rectangle((x0 + k, y0 + k, x1 - k, y1 - k), max(0, r - k), fill=FACE)


def strips(d, x0, y0, x1, y1, across, along):
    """Rows of LEDs along the long side, as a mat carries its strips."""
    w, h = x1 - x0, y1 - y0
    long_w = w >= h
    n_rows, n_dots = (across, along) if long_w else (across, along)
    rows = max(2, n_rows)
    dots = max(3, n_dots)
    for i in range(rows):
        t = (i + 0.5) / rows
        for j in range(dots):
            u = (j + 0.5) / dots
            cx, cy = (x0 + u * w, y0 + t * h) if long_w else (x0 + t * w, y0 + u * h)
            rr = max(S, min(w / dots if long_w else h / dots, h / rows if long_w else w / rows) * 0.16)
            d.rectangle((cx - rr, cy - rr, cx + rr, cy + rr), fill=LED)
        # the strip itself, a hairline through its LEDs
        if long_w:
            cy = y0 + t * h
            d.line((x0 + w * 0.02, cy, x1 - w * 0.02, cy), fill=LED, width=max(1, S // 2))
        else:
            cx = x0 + t * w
            d.line((cx, y0 + h * 0.02, cx, y1 - h * 0.02), fill=LED, width=max(1, S // 2))


def bolt(d, cx, cy, r):
    d.rectangle((cx - r, cy - r, cx + r, cy + r), fill=METAL)
    q = r * 0.45
    d.ellipse((cx - q, cy - q, cx + q, cy + q), fill=BOLT)


def litemat(name, w, h, feet_w, feet_h):
    """LiteGear's mat: a hard black frame, corner brackets and the tail box
    at the back."""
    im, d = canvas(w, h)
    W, H = w * S, h * S
    m = min(W, H)
    t = max(7 * S, round(m * 0.075))  # the frame's width
    r = round(m * 0.03)
    d.rounded_rectangle((0, 0, W - 1, H - 1), r, fill=FRAME)
    d.rounded_rectangle((t * 0.55, t * 0.55, W - 1 - t * 0.55, H - 1 - t * 0.55), r, outline=RIM, width=max(S, t // 8))
    face(d, t, t, W - 1 - t, H - 1 - t, max(0, r - t // 2))
    # strips run the long way, two to a foot across; LEDs every ~3"
    across = round(min(feet_w, feet_h) * 2.5)
    along = round(max(feet_w, feet_h) * 4)
    strips(d, t * 1.6, t * 1.6, W - 1 - t * 1.6, H - 1 - t * 1.6, across, along)
    # corner brackets
    b = t * 0.42
    for cx in (t * 0.5, W - 1 - t * 0.5):
        for cy in (t * 0.5, H - 1 - t * 0.5):
            bolt(d, cx, cy, b)
    # the tail box at the back, on the frame, with its amber band
    bw, bh = max(t * 2.4, W * 0.22), t * 1.15
    cx = W / 2
    d.rounded_rectangle((cx - bw / 2, H - 1 - bh, cx + bw / 2, H - 1), t * 0.2, fill=(70, 70, 74, 255))
    d.rectangle((cx - bw / 2 + t * 0.3, H - 1 - bh * 0.62, cx + bw / 2 - t * 0.3, H - 1 - bh * 0.38), fill=AMBER)
    save(im, w, h, name)


def infinimat(name, w, h, feet_w, feet_h):
    """Aputure's soft mat: rounded black skirt, a grommet at each corner, the face
    quilted in channels, a red tag and the control box at the back."""
    im, d = canvas(w, h)
    W, H = w * S, h * S
    m = min(W, H)
    t = max(8 * S, round(m * 0.08))
    r = round(m * 0.09)
    d.rounded_rectangle((0, 0, W - 1, H - 1), r, fill=FRAME)
    face(d, t, t, W - 1 - t, H - 1 - t, max(S, r - t))
    # quilted channels the long way, a foot apart, each with its row of
    # soft spots
    fx0, fy0, fx1, fy1 = t, t, W - 1 - t, H - 1 - t
    long_w = W >= H
    n = min(8, max(2, round(min(feet_w, feet_h) * 2)))
    for i in range(1, n):
        u = i / n
        if long_w:
            y = fy0 + u * (fy1 - fy0)
            d.line((fx0, y, fx1, y), fill=SHADE, width=max(S, t // 5))
        else:
            x = fx0 + u * (fx1 - fx0)
            d.line((x, fy0, x, fy1), fill=SHADE, width=max(S, t // 5))
    along = min(12, max(3, round(max(feet_w, feet_h) * 3)))
    for i in range(n):
        tt = (i + 0.5) / n
        for j in range(along):
            uu = (j + 0.5) / along
            if long_w:
                cx, cy = fx0 + uu * (fx1 - fx0), fy0 + tt * (fy1 - fy0)
                rx, ry = (fx1 - fx0) / along * 0.22, (fy1 - fy0) / n * 0.16
            else:
                cx, cy = fx0 + tt * (fx1 - fx0), fy0 + uu * (fy1 - fy0)
                rx, ry = (fx1 - fx0) / n * 0.16, (fy1 - fy0) / along * 0.22
            d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=LED)
    # a grommet at each corner, where it hangs from
    q = t * 0.28
    for cx in (r * 0.75, W - 1 - r * 0.75):
        for cy in (r * 0.75, H - 1 - r * 0.75):
            d.ellipse((cx - q, cy - q, cx + q, cy + q), outline=METAL, width=max(S, round(q * 0.45)))
    # red tag at a back corner, control box at the back's middle
    tag = t * 0.9
    d.rounded_rectangle((W - 1 - r - tag * 1.6, H - 1 - t * 0.9, W - 1 - r, H - 1 - t * 0.1), t * 0.15, fill=RED)
    bw, bh = max(t * 2.6, W * 0.2), t * 1.2
    d.rounded_rectangle((W / 2 - bw / 2, H - 1 - bh, W / 2 + bw / 2, H - 1), t * 0.25, fill=(64, 64, 68, 255))
    d.ellipse((W / 2 - t * 0.25, H - 1 - bh * 0.7, W / 2 + t * 0.25, H - 1 - bh * 0.7 + t * 0.5), fill=RED)
    save(im, w, h, name)


def bar(name, w, h, pixels, cap_ink, accent, accent2=None):
    """A pixel bar or tube, lying the long way: dark end caps, a lit body cut
    into its pixels, a ring of colour on one cap."""
    im, d = canvas(w, h)
    W, H = w * S, h * S
    cap = min(H * 0.55, W * 0.06)
    r = min(H / 2, cap)  # a tube rounds right off; a short bar keeps its corners
    d.rounded_rectangle((0, 0, W - 1, H - 1), r, fill=cap_ink)
    # the lit body
    pad = H * 0.1
    x0, x1 = cap, W - 1 - cap
    d.rounded_rectangle((x0, pad, x1, H - 1 - pad), (H - 2 * pad) * 0.3, fill=FACE)
    d.line((x0, H / 2 + (H / 2 - pad) * 0.55, x1, H / 2 + (H / 2 - pad) * 0.55), fill=SHADE, width=max(S, round(H * 0.08)))
    # pixel joints
    for i in range(1, pixels):
        x = x0 + (x1 - x0) * i / pixels
        d.line((x, pad, x, H - 1 - pad), fill=LED, width=max(S, round(H * 0.07)))
    # a band of colour on one cap, a button on the other
    if accent:
        d.rectangle((cap * 0.35, H * 0.06, cap * 0.7, H * 0.94), fill=accent)
    if accent2:
        d.rectangle((W - 1 - cap * 0.7, H * 0.06, W - 1 - cap * 0.35, H * 0.94), fill=accent2)
    else:
        d.ellipse((W - 1 - cap * 0.7, H / 2 - H * 0.12, W - 1 - cap * 0.4, H / 2 + H * 0.12), fill=METAL)
    save(im, w, h, name)


def mc_pro(name, w, h):
    """A palm-sized LED: black body, a diffuser filling its face, a small red
    mark and a screen at the back."""
    im, d = canvas(w, h)
    W, H = w * S, h * S
    m = min(W, H)
    r = m * 0.18
    d.rounded_rectangle((0, 0, W - 1, H - 1), r, fill=FRAME)
    t = m * 0.12
    face(d, t, t, W - 1 - t, H * 0.7, r * 0.5)
    for i in range(1, 5):
        x = t + (W - 1 - 2 * t) * i / 5
        d.line((x, t * 1.4, x, H * 0.7 - t * 0.4), fill=LED, width=S)
    d.rounded_rectangle((W * 0.3, H * 0.76, W * 0.7, H - 1 - t * 0.6), m * 0.03, fill=(96, 120, 140, 255))
    d.ellipse((W - 1 - t * 2.2, H * 0.77, W - 1 - t * 1.0, H * 0.77 + t * 1.2), fill=RED)
    save(im, w, h, name)


# ---- The pale grip: the pack's own shape, a firm edge and its material ----
#
# A white silk, a foam core, a hanging rag are pale on pale paper and vanish
# like the mats did. Their shapes are worth keeping (an angled frame's tilt,
# the stand's arm, a rag's wave), so these start from the pack's untouched
# picture, read from the pack itself so a second run never edges twice, and
# get a firm grey edge and a texture that says what they are made of.

EDGE = (112, 112, 118)


def pack_original(id):
    """The pack's own picture for one of our ids, from the pack in Drive."""
    import fso_import as fi
    for folder in fi.FOLDERS:
        base = os.path.join(fi.PACK, folder)
        for f in os.listdir(base):
            if f.endswith(".png") and fi.slug(fi.NAME_FIX.get(f[:-4], f[:-4])) == id:
                return Image.open(os.path.join(base, f)).convert("RGBA")
    raise SystemExit(f"fso_redraw: {id} is not in the pack at {fi.PACK}")


def firm(name, texture=None, edge=EDGE, k=None):
    """The pack's picture with a firm edge `k` px wide and a texture laid
    over its inside."""
    from PIL import ImageChops, ImageFilter
    im = pack_original(name)
    w, h = im.size
    a = im.getchannel("A")
    k = k or max(2, round(min(w, h) * 0.014))
    # Eroded on a margin of clear: a picture that runs to its own border
    # still gets its edge there.
    pad = Image.new("L", (w + 2 * k + 2, h + 2 * k + 2), 0)
    pad.paste(a, (k + 1, k + 1))
    inner = pad.filter(ImageFilter.MinFilter(2 * k + 1)).crop((k + 1, k + 1, k + 1 + w, k + 1 + h))
    if texture:
        layer = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
        texture(ImageDraw.Draw(layer), w * S, h * S, inner.getbbox() or (0, 0, w, h))
        layer = layer.resize((w, h), Image.LANCZOS)
        clip = ImageChops.multiply(layer.getchannel("A"), inner)
        layer.putalpha(clip)
        im = Image.alpha_composite(im, layer)
    ring = ImageChops.subtract(a, inner)
    im = Image.composite(Image.new("RGBA", (w, h), edge + (255,)), im, ring)
    im.putalpha(a)
    im.save(os.path.join(ASSETS, name + ".png"))


def weave(d, W, H, box):
    """Silk: a fine cross weave."""
    step = max(6 * S, min(W, H) / 12)
    ink = (0, 0, 0, 38)
    for i in range(-int(H / step) - 2, int(W / step) + 2):
        x = i * step
        d.line((x, 0, x + H, H), fill=ink, width=S)
        d.line((x + H, 0, x, H), fill=ink, width=S)


def board(d, W, H, box):
    """Foam core: the board's thickness, a second line just inside its edge."""
    x0, y0, x1, y1 = (v * S for v in box)
    t = max(3 * S, min(x1 - x0, y1 - y0) * 0.035)
    d.rectangle((x0 + t, y0 + t, x1 - t, y1 - t), outline=(0, 0, 0, 46), width=max(S, round(t * 0.35)))


def folds(d, W, H, box):
    """A hanging rag: soft folds down its fall."""
    x0, y0, x1, y1 = (v * S for v in box)
    n = max(5, round((x1 - x0) / (y1 - y0) * 2.2))
    for i in range(1, n):
        x = x0 + (x1 - x0) * i / n
        d.line((x, y0, x + (x1 - x0) * 0.012, y1), fill=(0, 0, 0, 34), width=max(2 * S, round((x1 - x0) * 0.004)))


def wraps(d, W, H, box):
    """A roll: the turns of gel wound on it, along its length."""
    x0, y0, x1, y1 = (v * S for v in box)
    for i in range(1, 4):
        x = x1 - (x1 - x0) * 0.035 * i
        d.line((x, y0, x, y1), fill=(0, 0, 0, 40), width=max(S, round((x1 - x0) * 0.004)))


def glare(d, W, H, box):
    """A mirror: two streaks of glare across the glass."""
    x0, y0, x1, y1 = (v * S for v in box)
    w, h = x1 - x0, y1 - y0
    for off, wd in ((0.25, 0.09), (0.45, 0.04)):
        x = x0 + w * off
        d.polygon([(x, y1), (x + w * wd, y1), (x + w * wd + h * 0.6, y0), (x + h * 0.6, y0)], fill=(255, 255, 255, 150))


def diffusion(d, W, H, box):
    """Lightbridge's diffusion face: a fine square mesh."""
    x0, y0, x1, y1 = (v * S for v in box)
    step = max(4 * S, (x1 - x0) / 14)
    ink = (0, 0, 0, 26)
    x = x0
    while x < x1:
        d.line((x, y0, x, y1), fill=ink, width=S)
        x += step
    y = y0
    while y < y1:
        d.line((x0, y, x1, y), fill=ink, width=S)
        y += step


DAY = (70, 150, 220, 255)
TUNG = (235, 140, 40, 255)


def tubes():
    """Quasar, Kino bare and the rest of the Pavo tubes: the Astera's
    drawing, a band of their colour on the cap (blue daylight, orange
    tungsten, one of each for bi-colour)."""
    out = {}
    for ft, w in ((1, 216), (2, 366), (4, 722)):
        out[f"quasar-{ft}ft-daylight"] = (w, 32, 1, DAY, None)
        out[f"quasar-{ft}ft-tungsten"] = (w, 32, 1, TUNG, None)
        out[f"quasar-{ft}ft-bi-color"] = (w, 32, 1, DAY, TUNG)
    for n, w in (("quasar-7in-q-led", 155), ("quasar-12in-q-led", 210), ("quasar-24in-q-led", 364)):
        out[n] = (w, 32 if w != 155 else 33, 1, None, None)
    for ft, w in ((2, 371), (4, 728)):
        out[f"kino-bare-{ft}ft-daylight"] = (w, 32, 1, DAY, None)
        out[f"kino-bare-{ft}ft-tungsten"] = (w, 32, 1, TUNG, None)
    for n, w, h, px in (("nanlite-pavo-15c", 444, 32, 8), ("nanlite-pavo-15x", 380, 33, 8),
                        ("nanlite-pavo-30c", 703, 32, 16), ("nanlite-pavo-30x", 658, 33, 16)):
        out[n] = (w, h, px, None, None)
    return {n: (lambda n=n, v=v: bar(n, v[0], v[1], v[2], CAP, v[3], v[4])) for n, v in out.items()}


def firmed():
    """The pale grip, each with its material."""
    out = {}
    for size in ("18x24", "2x3", "4x4"):
        out[f"{size}-white-silk"] = weave
        out[f"{size}-white-silk-angled"] = weave
    for n in ("4x4-foam-core", "4x4-foam-core-angled", "4x8-foam-core", "4x8-foam-core-angled"):
        out[n] = board
    for size in ("6x6", "8x8", "12x12", "20x20"):
        out[f"{size}-ultra-bounce-free-hanging"] = folds
        out[f"{size}-unbleached-muslin-free-hanging"] = folds
        out[f"{size}-grid-cloth-free-hanging"] = folds
    for n in ("frost-roll", "grid-roll", "light-grid-roll"):
        out[n] = wraps
    out["bounce-showcard"] = None
    out["bounce-showcard-blank"] = None
    out["mirror"] = glare
    for n in ("7x7", "15x15", "25x25", "50x50"):
        out[f"lightbridge-crls-c-diff-{n}"] = diffusion
    return {n: (lambda n=n, t=t: firm(n, t)) for n, t in out.items()}


# name: what draws it, at the pack's own size in pixels
REDRAWN = {
    "1x1-litemat": lambda: litemat("1x1-litemat", 180, 184, 1, 1),
    "2x2-litemat": lambda: litemat("2x2-litemat", 331, 341, 2, 2),
    "4x1-litemat": lambda: litemat("4x1-litemat", 179, 643, 1, 4),
    "4x2-litemat": lambda: litemat("4x2-litemat", 326, 642, 2, 4),
    "litemat-8": lambda: litemat("litemat-8", 589, 608, 3.5, 3.5),
    "aputure-infinimat-1x2": lambda: infinimat("aputure-infinimat-1x2", 347, 193, 2, 1),
    "aputure-infinimat-1x4": lambda: infinimat("aputure-infinimat-1x4", 685, 193, 4, 1),
    "aputure-infinimat-2x4": lambda: infinimat("aputure-infinimat-2x4", 685, 337, 4, 2),
    "aputure-infinimat-4x4": lambda: infinimat("aputure-infinimat-4x4", 699, 723, 4, 4),
    "aputure-infinimat-8x8": lambda: infinimat("aputure-infinimat-8x8", 1256, 1256, 8, 8),
    "aputure-infinibar-pb3": lambda: bar("aputure-infinibar-pb3", 173, 50, 4, CAP, RED),
    "aputure-infinibar-pb6": lambda: bar("aputure-infinibar-pb6", 336, 51, 8, CAP, RED),
    "aputure-infinibar-pb12": lambda: bar("aputure-infinibar-pb12", 665, 51, 16, CAP, RED),
    "aputure-mc-pro": lambda: mc_pro("aputure-mc-pro", 69, 47),
    "nanlite-pavo-6c": lambda: bar("nanlite-pavo-6c", 173, 31, 6, CAP, None),
    "astera-ax1-pixel-tube": lambda: bar("astera-ax1-pixel-tube", 596, 29, 16, CAP, None),
}


REDRAWN.update(tubes())
REDRAWN.update(firmed())


def main():
    for draw in REDRAWN.values():
        draw()
    print(len(REDRAWN), "redrawn")


if __name__ == "__main__":
    main()
