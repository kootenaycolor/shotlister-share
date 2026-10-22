#!/usr/bin/env python3
"""Bring the Film Set Objects pack into the diagram, as the pack drew it.

His ruling, 2026-09-27: the pack's own pictures, untouched — no redrawing,
no tracing. Except the flat ones he asked to have redrawn (2026-10-01):
tools/fso_redraw.py draws those over the pack's copies at the end. This copies each picture into engine/assets/fso/ and writes
engine/src/diagram/fso.rs: its name, its folder, its real size (the pack is
drawn at 561 px a metre) and what it is on a plan.

The pack is licensed to him for his own plots; it stays in the private repo.
Run again when the pack updates: python3 tools/fso_import.py
"""
import os, re, shutil
from PIL import Image

PACK = os.path.expanduser("~/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/"
                          "cinematography/documents/previs/20250219_FilmSetObjects/Individual PNGs")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "engine/assets/fso")
OUT = os.path.join(ROOT, "engine/src/diagram/fso.rs")
PX_PER_M = 561.0

# folder -> (library group, role)
FOLDERS = {
    "Cameras": ("Cameras", "camera"),
    "HMI Fixtures": ("HMI", "light"),
    "LED Fixtures": ("LED", "light"),
    "Tungsten Fixtures & Others": ("Tungsten & Others", "light"),
    "Fluorescent Fixtures": ("Fluorescent", "light"),
    "Solid Frames & Boards": ("Frames & Boards", "grip"),
    "Rags": ("Rags", "grip"),
    "Rolls, Cards & Light Beams": ("Rolls & Cards", "grip"),
    "Support & Rigging": ("Support & Rigging", "set"),
    "Rooms & Spaces": ("Rooms & Spaces", "set"),
    "Misc": ("Misc", "set"),
}
# Beam pictures, globes and density labels: the plan draws its own beams.
SKIP = re.compile(r"Degrees|Globe|Density .* Label")
PEOPLE = {"Standing Person": "standing", "Walking Person": "walking", "Sitting Person": "seated"}
NOT_LIGHTS = {"Mirror"}
# Where the pack's size is off, the maker's (metres across the picture's width).
TRUE_WIDTH = {"Mole Tweenie": 0.24}
FOOT = 0.3048
# Pieces whose name says their size are that size (2026-09-30: a 10' rail
# was 9' 9", a 20' x 40' room 39' 2" x 20' 8" — the pack draws at about 561 px
# a metre, margins and all). These are held to the name.
LENGTHS = re.compile(r"Speed Rail|Box Truss|Polecat|Track Section|Slider|Paper")
# What a piece is where its name does not say: the size it is sold or built
# at, in feet across × along (None keeps the picture's shape).
KNOWN = {
    "Door": (3.0, None),
    "Small Window": (3.0, None),
    "Large Window": (5.0, None),
    # A queen: five feet by six foot eight.
    "Bed": (5.0, 80 / 12),
    "Bed One Person Left Back": (5.0, 80 / 12),
    "Bed One Person Left Side": (5.0, 80 / 12),
    "Bed One Person Right Back": (5.0, 80 / 12),
    "Bed One Person Right Side": (5.0, 80 / 12),
    "Bed Two People Backs": (5.0, 80 / 12),
}


def true_size(name, w, h):
    """The size a piece's name says it is, in metres as the picture lies —
    or None where the name says nothing."""
    if name in KNOWN:
        fw, fh = KNOWN[name]
        return (fw * FOOT, fh * FOOT) if fh else (fw * FOOT, h * fw * FOOT / w)
    m = re.match(r"(\d+)' x (\d+)' ", name)
    if m:  # a room: its two sides, the longer the way the picture is longer
        a, b = sorted((float(m.group(1)), float(m.group(2))))
        return (b * FOOT, a * FOOT) if w >= h else (a * FOOT, b * FOOT)
    m = re.search(r"(\d+)(?:'|ft)(?: |$)", name)
    if m and LENGTHS.search(name):  # a length: its long side, kept in shape
        k = float(m.group(1)) * FOOT / max(w, h)
        return (w * k, h * k)
    m = re.match(r"(\d+)x(\d+) ", name)
    if m and "Lightbridge" not in name:
        # A frame, flag, rag or canopy: inches past twenty (an 18x24 flag),
        # else feet (a 20x20). The picture's width is whichever side it is
        # nearest, kept in shape so a frame's ears and arm stay where the
        # pack drew them.
        a, b = float(m.group(1)), float(m.group(2))
        if max(a, b) > 20:
            a, b = a / 12, b / 12
        wf = w / FOOT
        side = a if abs(a - wf) / a <= abs(b - wf) / b else b
        k = side * FOOT / w
        return (w * k, h * k)
    return None
# Which way a lamp's front points in its picture, where it is not the top —
# checked by eye, lamp by lamp, 2026-09-27. Three splayed bars are open
# barn doors; a softbox or pancake opens toward its white face.
FACES = {
    "down": ["Arri Fresnel 18-12", "Arri M18", "Arri M40", "Arri M8", "Arri M90", "Arrimax 18-12", "2K LED",
             "Arri L10", "Arri L5", "Arri L7", "Mole 1600w TenorLED", "Mole 900w SeniorLED", "Arri 150", "Arri 300",
             "Arri 650", "Arri 2K Plus Arrilite", "Arri T12", "Arri T24", "Briese Focus 100", "Briese Focus 180",
             "Briese Focus 220", "Briese Focus 330", "Large Pancake", "Medium Pancake", "Large Softbox", "Small Softbox"],
    "right": ["ETC Source Four LED Ellipsoidal", "Diva 200 Top Long", "Diva 200 Top Upright", "Diva 400 Top Long",
              "Diva 400 Top Upright", "Gaffer 4x4' Top Long", "Gaffer 4x4' Top Upright"],
    "left": ["Ellipsoidal"],
}
# How far a picture is turned so it faces east, the way the plan faces things.
TURN = {"up": 90.0, "down": -90.0, "right": 0.0, "left": 180.0}
# Lamps that glow all round rather than throw forward.
OMNI = re.compile(r"B7C|Bare Bulb|China Ball|Lamp with Shade|Quasar|Kino Bare|Pavo|Infinibar|Pixel Tube|Softube|"
                  r"Street Light|Spacelight|SkyPan")

# The pack's spelling slips, put right in the name only.
NAME_FIX = {"Dany Dolly with Rails": "Dana Dolly with Rails"}


def slug(s):
    s = s.lower().replace("+", "plus ").replace("'", "ft ").replace('"', "in ")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def beam(name, folder):
    n = name.lower()
    if re.search(r"back|end$", n):
        return 0.0, 0.0, 0.0
    if OMNI.search(name):
        k = 3200.0 if "tungsten" in n or "sodium" in n or folder == "Tungsten Fixtures & Others" else 5600.0
        return 360.0, 3.0, 4300.0 if "bi-color" in n else k
    k = 3200.0 if folder == "Tungsten Fixtures & Others" or "tungsten" in n else 5600.0
    if "bi-color" in n:
        k = 4300.0
    if re.search(r"china|bare bulb|lamp with shade|spacelight|lantern|dome|pixel tube|ribbon", n):
        return 360.0 if re.search(r"china|bare bulb|lamp|spacelight|lantern|tube|ribbon", n) else 110.0, 4.0, k
    if re.search(r"leko|ellipsoidal|spotlight|projector lens|molebeam|narrow|par|flashlight|spot$", n):
        return 25.0, 12.0, k
    if re.search(r"fresnel|m18|m40|m8\b|m90|joker|arrimax|t12|t24|mole baby|junior|tweenie|arri \d|arrilite|l10|l7|l5|orbiter", n):
        return 45.0, 10.0, k
    if re.search(r"softbox|pancake|skypanel|litemat|infinimat|mat|tile|kino|diva|gaffer|celeb|astra|mixpanel|pavo|quasar|voyager|spider|softlite|molefay|briese|sputnik|panel|s\d+c", n):
        return 100.0, 6.0, k
    return 60.0, 8.0, k


def main():
    os.makedirs(ASSETS, exist_ok=True)
    for f in os.listdir(ASSETS):
        os.remove(os.path.join(ASSETS, f))
    rows, seen = [], set()
    for folder, (group, role) in FOLDERS.items():
        for f in sorted(os.listdir(os.path.join(PACK, folder))):
            if not f.endswith(".png"):
                continue
            name = NAME_FIX.get(f[:-4], f[:-4])
            if SKIP.search(name):
                continue
            id = "fso-" + slug(name)
            if id in seen:
                continue
            seen.add(id)
            src = os.path.join(PACK, folder, f)  # the file keeps the pack's own name
            w, h = Image.open(src).size
            shutil.copyfile(src, os.path.join(ASSETS, id[4:] + ".png"))
            r = role
            if name in PEOPLE:
                r = "person"
            elif role == "light" and name in NOT_LIGHTS:
                r = "grip"
            b = beam(name, folder) if r == "light" else (0.0, 0.0, 0.0)
            if r == "light" and b[0] == 0.0:
                r = "fixture"  # a back or end view: a light seen from behind, giving none
            face = next((f for f, names in FACES.items() if name in names), "up")
            turn = {"camera": TURN[face], "light": TURN[face], "fixture": TURN[face], "person": -90.0}.get(r, 0.0)
            scale = (TRUE_WIDTH[name] / w) if name in TRUE_WIDTH else 1.0 / PX_PER_M
            size = true_size(name, w * scale, h * scale) or (w * scale, h * scale)
            rows.append((id, name, group, r, PEOPLE.get(name, ""), turn, w, h, *size, *b))
    with open(OUT, "w") as o:
        o.write("//! The Film Set Objects pack, as the pack drew it. Written by\n"
                "//! `tools/fso_import.py` — edit that, not this.\n//!\n"
                "//! A picture faces whichever way the pack drew it; `turn` sets it east.\n"
                "//! `w`/`h` are its size in metres as the image lies, before any turn.\n\n"
                "pub struct Art {\n    pub id: &'static str,\n    pub name: &'static str,\n"
                "    pub group: &'static str,\n    /// `camera`, `light`, `fixture` (a light giving none), `grip`, `set`, `person`.\n"
                "    pub role: &'static str,\n    /// For a person: the pose it shows.\n    pub pose: &'static str,\n"
                "    /// Degrees the picture is turned to face east, the way the plan faces things.\n    pub turn: f64,\n"
                "    pub px_w: u32,\n    pub px_h: u32,\n    pub w: f64,\n    pub h: f64,\n"
                "    pub beam: f64,\n    pub reach: f64,\n    pub kelvin: f64,\n    /// The PNG, or empty where the build leaves the pack out.\n    pub png: &'static [u8],\n}\n\n"
                "/// The picture itself, where the build carries the pack (the Mac and\n"
                "/// iPhone); empty in the portal's builds, which fetch the file.\n"
                "#[cfg(feature = \"fso-art\")]\nmacro_rules! png {\n    ($p:literal) => {\n        include_bytes!($p)\n    };\n}\n"
                "#[cfg(not(feature = \"fso-art\"))]\nmacro_rules! png {\n    ($p:literal) => {\n        &[]\n    };\n}\n\n"
                "pub static ART: &[Art] = &[\n")
        for (id, name, group, r, pose, turn, pw, ph, w, h, bm, reach, k) in rows:
            o.write(f'    Art {{ id: "{id}", name: {rust(name)}, group: "{group}", role: "{r}", pose: "{pose}", turn: {turn:.1f}, '
                    f'px_w: {pw}, px_h: {ph}, w: {w:.4f}, h: {h:.4f}, beam: {bm:.1f}, reach: {reach:.1f}, kelvin: {k:.1f}, '
                    f'png: png!("../../assets/fso/{id[4:]}.png") }},\n')
        o.write("];\n\npub fn find(id: &str) -> Option<&'static Art> {\n    ART.iter().find(|a| a.id == id)\n}\n")
    print(len(rows), "pictures")
    import fso_redraw
    fso_redraw.main()


def rust(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


if __name__ == "__main__":
    main()
