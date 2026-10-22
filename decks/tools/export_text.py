#!/usr/bin/env python3
"""Write <deck>/text.md from the template's data-t strings.

    python3 export_text.py <deck-folder>

Run once when a template is new, or again after adding data-t keys. Existing
wording in text.md wins, so this never overwrites edits.
"""
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from deckcore import Deck
from text_io import to_markdown, parse_markdown

deck = Deck(sys.argv[1])
tpl = deck.template.read_text()
first = tpl.index("<!--SECTION:")
body = tpl[first:tpl.rindex("</body>")]
parts = re.split(r"<!--SECTION:([a-z_]+)-->", body)
sections = [(parts[i], parts[i+1]) for i in range(1, len(parts), 2)
            if parts[i] not in ("collage", "__projects__")]

labels = deck.theme.get("section_labels", {})
import text_io
text_io.SECTION_LABELS = {k: labels.get(k, k.title()) for k, _ in sections}

md = to_markdown(sections)
if deck.text_md.exists():
    keep = parse_markdown(deck.text_md.read_text())
    out = []
    cur = None
    for line in md.splitlines():
        m = re.match(r"^###\s+([A-Za-z0-9_.-]+)\s*$", line)
        if m:
            cur = m.group(1)
            out.append(line); continue
        out.append(line)
    md = "\n".join(out)
deck.text_md.write_text(md)
print(f"wrote {deck.text_md} ({len(md.splitlines())} lines)")
