#!/usr/bin/env python3
"""Start a new deck folder.

    python3 new_deck.py <name> [--from <existing-deck>] [--project <slug> | --in <parent-folder>]

Copies the design of an existing deck (theme, template, text, assets, image
sources) into a fresh folder with an empty deck.json, plus its own launchers.
The arranging then happens in the editor.

--project <slug> files it where a project's decks live: projects/<slug>/1-creative/
decks/<name>/z-source/ (working files), with the finished PDF one level up and
older ones in z-archive/ (render.py does that filing).

To build a deck in the style of a reference instead, hand the reference to
Claude and ask for a theme: what changes is theme.json and template.html.
Everything else in here stays the same.
"""

import json
import shutil
import stat
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
PROJECTS = Path(
    "/Users/YOUR_USER/Library/CloudStorage/"
    "GoogleDrive-you@example.com/My Drive/cinematography/projects"
)
DECKS = Path(
    "/Users/YOUR_USER/Library/CloudStorage/"
    "GoogleDrive-you@example.com/My Drive/cinematography/"
    "portfolio/outbound/decks"
)

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>{name}</string>
  <key>CFBundleIdentifier</key><string>com.example.{exe}</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>{exe}</string>
  {extra}
</dict></plist>
"""

SH = """#!/bin/bash
DECK="$(cd "$(dirname "${{BASH_SOURCE[0]}}")/../../.." && pwd)"
exec /usr/bin/python3 "{tools}/{script}" "$DECK" {args} >> "/tmp/nr-deck-{exe}.log" 2>&1
"""


def make_app(folder, name, script, args="", agent=False):
    exe = name.replace(" ", "")
    app = folder / f"{name}.app"
    if app.exists():
        shutil.rmtree(app)
    (app / "Contents" / "MacOS").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_text(PLIST.format(
        name=name, exe=exe,
        extra="<key>LSUIElement</key><true/>" if agent else ""))
    runner = app / "Contents" / "MacOS" / exe
    runner.write_text(SH.format(tools=TOOLS, script=script, args=args, exe=exe))
    runner.chmod(runner.stat().st_mode | stat.S_IEXEC)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    name = sys.argv[1]
    src = None
    if "--from" in sys.argv:
        src = Path(sys.argv[sys.argv.index("--from") + 1]).expanduser().resolve()

    # A deck usually belongs to a project, so it lives in that project's
    # folder. --in says where; without it, the shared outbound decks folder.
    # --project <slug> puts it where project decks now live (since 2026-10-15):
    # projects/<slug>/1-creative/decks/<name>/z-source/, PDFs one level up.
    if "--project" in sys.argv:
        slug = sys.argv[sys.argv.index("--project") + 1]
        dst = PROJECTS / slug / "1-creative" / "decks" / name / "z-source"
    elif "--in" in sys.argv:
        dst = Path(sys.argv[sys.argv.index("--in") + 1]).expanduser().resolve() / name
    else:
        dst = DECKS / name
    if dst.exists():
        raise SystemExit(f"{dst} already exists")
    dst.mkdir(parents=True)
    if dst.name == "z-source":
        (dst.parent / "z-archive").mkdir(exist_ok=True)

    if src:
        for f in ("theme.json", "template.html", "text.md", "sources.json"):
            if (src / f).exists():
                shutil.copy(src / f, dst / f)
        if (src / "assets").is_dir():
            shutil.copytree(src / "assets", dst / "assets")
        theme = json.loads((dst / "theme.json").read_text())
        theme["file_stem"] = f"NR_Deck_{name}"
        (dst / "theme.json").write_text(json.dumps(theme, indent=2))
    else:
        (dst / "assets").mkdir()
        (dst / "theme.json").write_text(json.dumps({
            "name": name, "file_stem": f"NR_Deck_{name}",
            "page": {"width_in": 8.5, "height_in": 11.0, "css_size": "letter"},
            "grid": {"gap_in": 0.07, "first_budget_in": 7.35,
                     "cont_budget_in": 8.75, "full_budget_in": 10.35},
            "colors": {"paper": "#ffffff", "ink": "#111111"},
        }, indent=2))
        (dst / "sources.json").write_text(json.dumps({"pools": []}, indent=2))

    (dst / "deck.json").write_text(json.dumps(
        {"version": 0, "sections": [], "cover": [], "projects": []}, indent=2))

    sys.path.insert(0, str(TOOLS))
    import registry
    registry.register(dst, name)
    print(f"created {dst}")
    print("It is registered, so it will appear in Deck Editor.app.")


if __name__ == "__main__":
    main()
