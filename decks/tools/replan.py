#!/usr/bin/env python3
"""Re-flow a deck's reference pages so each one fills its page.

    python3 replan.py <deck-folder> [--dry]

Only the page breaks and who shares a row change. The images and their order
are left exactly as they are: pages are contiguous slices of what is already
there. Every run leaves the previous deck.json in the deck's .history/.
"""

import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deckcore import Deck, load_dims, plan_pages  # noqa: E402


def note_lines(note, per_line=78):
    return 0 if not note else max(1, -(-len(note) // per_line))


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: replan.py <deck-folder> [--dry]")
    dry = "--dry" in sys.argv
    deck = Deck(sys.argv[1])
    groups, paths, labels = deck.scan()
    dims = load_dims(paths)
    data = json.loads(deck.deck_file.read_text())

    grid = deck.theme["grid"]
    line = float(grid.get("note_line_in", 0.4431))
    base = int(grid.get("note_lines_baseline", 3))
    notes = deck.theme.get("project_notes", {})
    content_w = deck.page_w - 2 * deck.gap

    for p in data.get("projects", []):
        keys = [k for pg in p.get("pages", []) for r in pg for k in r if k in paths]
        if not keys:
            continue
        ars = [dims.get(k, [16, 9])[0] / dims.get(k, [16, 9])[1] for k in keys]
        note = notes.get(p["slug"], "")
        first_h = deck.first_budget + (base - note_lines(note)) * line
        plan = plan_pages(ars, content_w, deck.gap, first_h, deck.cont_budget)

        pages, report = [], []
        for n, (i, j, got) in enumerate(plan):
            parts, hs, w, s, filled, _ = got
            page, at = [], i
            for size in parts:
                page.append(keys[at:at + size])
                at += size
            pages.append(page)
            budget = first_h if n == 0 else deck.cont_budget
            report.append(f"{j - i:>3} imgs {str(parts):<16} "
                          f"width {w * 100:5.1f}%  crop {(s - 1) * 100:4.1f}%  "
                          f"fill {sum(hs) / budget * 100:5.1f}%")
        was = len(p["pages"])
        p["pages"] = pages
        print(f'{p["slug"]:<32} {len(keys):>3} images  {was}pp -> {len(pages)}pp')
        for r in report:
            print("     " + r)

    if dry:
        print("\ndry run; nothing written")
        return
    stamp = time.strftime("%H%M%S")
    shutil.copy(deck.deck_file, deck.history / f"deck-{stamp}-before-replan.json")
    data["version"] = int(data.get("version", 0)) + 1
    deck.deck_file.write_text(json.dumps(data, indent=2))
    print(f"\nwrote {deck.deck_file} (version {data['version']})")


if __name__ == "__main__":
    main()
