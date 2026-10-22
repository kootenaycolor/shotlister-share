#!/usr/bin/env python3
"""What `publish.py` sends the editor to draw a sheet with — checked, not read.

The paper kit is the print design re-addressed for the editor, and three things
in that re-addressing went wrong silently on 2026-09-07: a sheet's own class was
dropped, the design's `:root` variables matched nothing inside a shadow root,
and `body`'s typeface never reached the sheet. Each is a line of regex, and a
line of regex is exactly the kind of thing that breaks again without a sound.

    python3 decks/checks/kit.py
"""
import json
import subprocess
import sys
import tempfile
import types
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
import publish                                   # noqa: E402
from deckcore import Deck                        # noqa: E402
from arrangement import Arrangement              # noqa: E402

TEMPLATE = """<!DOCTYPE html><html><head><meta charset="utf-8"><style>
@font-face{font-family:PF;src:url('assets/fonts/PF.ttf')}
:root{--field:#7E1524;--rose:#FFDADD}
html,body{background:var(--ground)}
body{font-family:PF,Georgia,serif;color:#fff;font-size:10pt}
.body{x:y} tbody{z:1}
.page{width:8.5in;height:11in}
.page.red{background-color:var(--field)}
</style></head><body>
<!--SECTION:cover-->
<div class="page red" style="--x:1">
  <div class="t1" data-t="cover.title1">Cover</div>
</div>
<!--HEAD:opening:2.4-->
<div class="band spec"><p data-t="opening.b1"></p></div>
<!--/HEAD-->
<!--SECTION:__p_opening__-->
<!--SECTION:plain-->
<div class="page">
  <p data-t="plain.b1"></p>
</div>
</body></html>"""

fails = 0


def check(what, got, want):
    global fails
    if got == want:
        print(f"  PASS  {what}")
    else:
        fails += 1
        print(f"  FAIL  {what} — got {got!r}, wanted {want!r}")


with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    (d / "template.html").write_text(TEMPLATE)
    (d / "theme.json").write_text(json.dumps({"page": {}, "grid": {}}))
    (d / "deck.json").write_text("{}")
    (d / "assets/fonts").mkdir(parents=True)
    (d / "assets/fonts/PF.ttf").write_bytes(b"not really a font")
    (d / "arrangement.json").write_text(json.dumps({"version": 1, "sections": [
        {"id": "cover", "on": True}, {"id": "opening", "on": True, "groups": []},
        {"id": "plain", "on": True}]}))

    sent = []

    def fake_run(args, **kw):
        sent.append(args)
        return subprocess.CompletedProcess(args, 0, "", "")
    publish.subprocess = types.SimpleNamespace(run=fake_run, CompletedProcess=subprocess.CompletedProcess)

    kit = publish.paper_kit(Deck(str(d)), Arrangement.load(d / "arrangement.json"), project="film")
    css = kit["css"]

    print("— the sheet's dress —")
    check("a red page says it is red", kit["blocks"]["cover"]["cls"], "red")
    check("…and keeps its inline style", kit["blocks"]["cover"]["style"], "--x:1")
    check("…and its contents, without the wrapper", kit["blocks"]["cover"]["html"],
          '<div class="t1" data-t="cover.title1">Cover</div>')
    check("a plain page says nothing", kit["blocks"]["plain"]["cls"], "")
    check("a head keeps its band, which paints itself", kit["heads"]["opening"]["cls"], "")
    check("…and its inches", kit["heads"]["opening"]["inches"], 2.4)

    print("— the stylesheet, re-addressed —")
    check(":root is gone", ":root" in css, False)
    check("…its variables live on the sheet", ".page{--field:#7E1524;--rose:#FFDADD}" in css, True)
    check("body's typeface reaches the sheet", ".page{font-family:PF,Georgia,serif;color:#fff;font-size:10pt}" in css, True)
    check("body's background does not", "var(--ground)" in css, False)
    check(".body and tbody are left alone", ".body{x:y} tbody{z:1}" in css, True)
    check("the sheet's own rules survive", ".page.red{background-color:var(--field)}" in css, True)

    print("— the typefaces —")
    check("the font went up as a document",
          any(any("/docs/" in str(x) for x in a) and a[-1] == "font/ttf" for a in sent), True)
    check("…and the rule points at it the editor's way", "url('../pic/" in css and ".ttf')" in css, True)

print(f"\n{'all good' if not fails else f'{fails} failed'}")
sys.exit(1 if fails else 0)
