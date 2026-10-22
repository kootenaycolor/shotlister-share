#!/usr/bin/env python3
"""The edge of each lamp picture in the pack, for the plan to draw behind it.

His ruling, 2026-09-27, stands: the pack's pictures are drawn untouched. This
only measures where each lamp picture's edge runs, so the plan can lay a
patch of paper with an ink edge *behind* it (SL-1334, 2026-10-01: "Titan
tubes just disappear into the frame") — Scenario's way, a lamp that reads on
any fill.

Reads engine/assets/fso/*.png for every light in fso.rs and writes
engine/src/diagram/fso_outline.rs. Run again after tools/fso_import.py:
python3 tools/fso_outlines.py
"""
import os, re
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FSO = os.path.join(ROOT, "engine/src/diagram/fso.rs")
OUT = os.path.join(ROOT, "engine/src/diagram/fso_outline.rs")
ROW = re.compile(r'id: "(fso-[^"]+)".*?role: "(light|fixture)".*?png: png!\("\.\./\.\./assets/fso/([^"]+)"\)')


def outline(path):
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if img is None or img.ndim < 3 or img.shape[2] < 4:
        return None
    h, w = img.shape[:2]
    a = (img[:, :, 3] > 40).astype(np.uint8) * 255
    # Pad so a closing at the border cannot clip, then knit near parts
    # (a yoke, a handle) into one body.
    pad = max(4, round(max(w, h) * 0.04))
    a = cv2.copyMakeBorder(a, pad, pad, pad, pad, cv2.BORDER_CONSTANT, 0)
    k = max(3, round(min(w, h) * 0.06) | 1)
    a = cv2.morphologyEx(a, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    found, _ = cv2.findContours(a, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not found:
        return None
    total = sum(cv2.contourArea(c) for c in found) or 1.0
    keep = [c for c in found if cv2.contourArea(c) >= total * 0.03]
    rings = []
    for c in keep:
        eps = 0.004 * cv2.arcLength(c, True)
        p = cv2.approxPolyDP(c, eps, True).reshape(-1, 2)
        if len(p) < 3:
            continue
        rings.append([((x - pad) / w, (y - pad) / h) for x, y in p])
    return rings or None


def main():
    src = open(FSO).read()
    rows = ROW.findall(src)
    out = [
        "//! Where each lamp picture's edge runs, for the plan to draw a patch of",
        "//! paper and an ink edge behind it. Written by `tools/fso_outlines.py`",
        "//! — run that, not this. Points are fractions of the picture, across",
        "//! then down, before any turn; a picture may have more than one ring.",
        "",
        "pub static OUTLINE: &[(&str, &[&[(f32, f32)]])] = &[",
    ]
    n = 0
    for aid, _role, png in rows:
        rings = outline(os.path.join(ROOT, "engine/assets/fso", png))
        if not rings:
            continue
        rs = ", ".join("&[" + ", ".join(f"({x:.3f}, {y:.3f})" for x, y in r) + "]" for r in rings)
        out.append(f'    ("{aid}", &[{rs}]),')
        n += 1
    out += [
        "];",
        "",
        "/// A lamp picture's edge, by its id.",
        "pub fn find(id: &str) -> Option<&'static [&'static [(f32, f32)]]> {",
        "    OUTLINE.iter().find(|(a, _)| *a == id).map(|(_, r)| *r)",
        "}",
        "",
    ]
    open(OUT, "w").write("\n".join(out))
    print(f"{n} of {len(rows)} lamp pictures outlined -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
