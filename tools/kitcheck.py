#!/usr/bin/env python3
"""One look everywhere: every app's copy of the kit says what design/kit/kit.json says.

    python3 tools/kitcheck.py [--console WEB_INDEX_HTML] [--console-ios KIT_SWIFT]

Checks shared/Kit.swift (Studio Mac and iPhone) and hub/public/kit.css (the
portal) always; the two Projects Console mirrors when found (their default
places, or the paths given). Exit 1 on any difference.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = json.load(open(os.path.join(ROOT, "design/kit/kit.json")))
HOME = os.path.expanduser("~")

bad = []
seen = []

SIZES = {k: v["size"] for k, v in KIT["type"].items()}
SPACE = KIT["space"]
RADIUS = KIT["radius"]
COLORS = {k: (v["light"].upper(), v["dark"].upper()) for k, v in KIT["color"].items()}
SWIFT_SPACE = ["xs", "s", "m", "l", "xl", "xxl"]


def swift(path, colors_needed):
    text = open(path).read()
    seen.append(path)

    def block(name):
        m = re.search(r"enum %s \{(.*?)\n    \}" % name, text, re.S)
        return m.group(1) if m else ""

    size = dict(re.findall(r"static let (\w+): CGFloat = ([0-9.]+)", block("Size")))
    for k, v in SIZES.items():
        if float(size.get(k, -1)) != v:
            bad.append(f"{path}: Size.{k} is {size.get(k)}, kit says {v}")
    space = dict(re.findall(r"static let (\w+): CGFloat = ([0-9.]+)", block("Space")))
    for name, v in zip(SWIFT_SPACE, SPACE):
        if float(space.get(name, -1)) != v:
            bad.append(f"{path}: Space.{name} is {space.get(name)}, kit says {v}")
    radius = dict(re.findall(r"static let (\w+): CGFloat = ([0-9.]+)", block("Radius")))
    for k, v in RADIUS.items():
        if float(radius.get(k, -1)) != v:
            bad.append(f"{path}: Radius.{k} is {radius.get(k)}, kit says {v}")
    pairs = {k: (l.upper(), d.upper()) for k, l, d in re.findall(r'static let (\w+) = Pair\("(\w{6})", "(\w{6})"\)', text)}
    for k in colors_needed:
        if pairs.get(k) != COLORS[k]:
            bad.append(f"{path}: Ink.{k} is {pairs.get(k)}, kit says {COLORS[k]}")
    for side, key in (("Light", "light"), ("Dark", "dark")):
        w = re.search(r"static let sectionWash%s = ([0-9.]+)" % side, text)
        if not w or float(w.group(1)) != KIT["sectionWash"][key]:
            bad.append(f"{path}: sectionWash{side} differs from kit ({KIT['sectionWash'][key]})")
    soon = re.search(r"static let soonDays = (\d+)", text)
    if not soon or int(soon.group(1)) != KIT["soonDays"]:
        bad.append(f"{path}: soonDays differs from kit ({KIT['soonDays']})")


def css(path, colors_needed):
    text = open(path).read()
    seen.append(path)
    vals = dict(re.findall(r"(--k-[\w-]+):\s*([^;]+);", text))
    for k, v in SIZES.items():
        if vals.get(f"--k-{k}", "").strip() != f"{v}px":
            bad.append(f"{path}: --k-{k} is {vals.get(f'--k-{k}')}, kit says {v}px")
    for i, v in enumerate(SPACE, 1):
        if vals.get(f"--k-s{i}", "").strip() != f"{v}px":
            bad.append(f"{path}: --k-s{i} is {vals.get(f'--k-s{i}')}, kit says {v}px")
    if "display" not in KIT:
        pass
    elif path.endswith("kit.css"):
        if vals.get("--k-display", "").strip() != f"{KIT['display']['size']}px":
            bad.append(f"{path}: --k-display is {vals.get('--k-display')}, kit says {KIT['display']['size']}px")
        for side, key in (("l", "light"), ("d", "dark")):
            if float(vals.get(f"--k-section-wash-{side}", "-1")) != KIT["sectionWash"][key]:
                bad.append(f"{path}: --k-section-wash-{side} differs from kit")
    for k, v in RADIUS.items():
        if vals.get(f"--k-r-{k}", "").strip() != f"{v}px":
            bad.append(f"{path}: --k-r-{k} is {vals.get(f'--k-r-{k}')}, kit says {v}px")
    for k in colors_needed:
        light, dark = COLORS[k]
        for side, want in (("l", light), ("d", dark)):
            got = vals.get(f"--k-{k}-{side}", "").strip().lstrip("#").upper()
            if got != want:
                bad.append(f"{path}: --k-{k}-{side} is #{got}, kit says #{want}")


args = sys.argv[1:]
def arg(flag, default):
    return args[args.index(flag) + 1] if flag in args else default

ALL = list(COLORS)
WEB = [k for k in ALL if not k.startswith("phone")]
swift(os.path.join(ROOT, "shared/Kit.swift"), ALL)
css(os.path.join(ROOT, "hub/public/kit.css"), WEB)
console_web = arg("--console", os.path.join(HOME, "Developer/projects-console/web/index.html"))
if os.path.exists(console_web) and "--k-title" in open(console_web).read():
    css(console_web, WEB)
console_ios = arg("--console-ios", os.path.join(HOME, "Developer/project-console-ios/ProjectsConsole/Sources/Model/Kit.swift"))
if os.path.exists(console_ios):
    swift(console_ios, ALL)

for b in bad:
    print("  " + b)
print(f"kitcheck: {len(seen)} copies checked, {len(bad)} differences")
sys.exit(1 if bad else 0)
