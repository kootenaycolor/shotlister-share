#!/usr/bin/env python3
"""Does a publish from the Mac keep everything the portal already had?

**The bug this closes.** `push_record` built a fresh object and put it, so every
key on the deck's record that this Mac does not itself write was deleted by any
publish — and nothing said so, because nothing here knew those keys existed.
Three were being lost: `crop` (his per-side crops), `notion` (the page linked in
the inspector) and `group.across` (how many frames he put across a line, which
since the portal began printing the PDF decides the printed page).

Fixing the three by name would have been the wrong fix. The fault is that the
Mac round-trips the record through models narrower than the record, so the test
is a *stranger key* — one no version of this code has heard of. If that survives,
so will the next setting the editor grows.

    python3 decks/checks/record.py        # no hub, no network
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import publish                                          # noqa: E402
from arrangement import Arrangement, Section            # noqa: E402

ok = True


def check(label, got, want):
    global ok
    good = got == want
    ok = ok and good
    print(f"  {'PASS' if good else 'FAIL'}  {label}")
    if not good:
        print(f"        wanted {want!r}\n        got    {got!r}")


ON_PORTAL = {
    "version": 1, "name": "Visual Bible", "slug": "bible",
    "words": {"cover.title1": "Call Her <i>Back</i>"},
    "pictures": {"aaa": {"name": "aaa.jpg", "ar": 1.78}},
    # keys this Mac never writes
    "crop": {"aaa": {"paper": "50% 20%"}},
    "notion": {"url": "https://notion.so/whatever"},
    "somethingNew": {"invented": "after this code was written"},
    "sections": [{
        "id": "opening", "title": "Opening", "on": True,
        "unheardOf": "a section key from a later editor",
        "groups": [{
            "emphasis": "quiet", "pictures": ["aaa"], "ratio": "4/3",
            "across": {"paper": 3, "web": 2},
            "alsoUnheardOf": "a group key from a later editor",
        }],
    }],
}

print("— the arrangement round trip —")
arr = Arrangement([Section.of_json(s) for s in ON_PORTAL["sections"]])
back = [s.as_json() for s in arr.sections]
g_in, g_out = ON_PORTAL["sections"][0]["groups"][0], back[0]["groups"][0]
check("how many across survives", g_out.get("across"), g_in["across"])
check("the grid ratio survives", g_out.get("ratio"), g_in["ratio"])
check("a group key nobody modelled survives", g_out.get("alsoUnheardOf"), g_in["alsoUnheardOf"])
check("a section key nobody modelled survives", back[0].get("unheardOf"),
      ON_PORTAL["sections"][0]["unheardOf"])
check("and the whole section is unchanged", back, ON_PORTAL["sections"])

print("— what a publish would put —")
wrote = {}


def fake_run(cmd, *a, **k):
    for i, part in enumerate(cmd):
        if part == "--file":
            wrote.update(json.loads(Path(cmd[i + 1]).read_text()))
    class R:
        returncode = 0
        stdout = stderr = ""
    return R()


publish.subprocess.run = fake_run
publish.push_record("film", None, "bible", "Visual Bible", arr,
                    ON_PORTAL["words"], {"bbb": {"name": "bbb.jpg", "ar": 1.5}},
                    keep=ON_PORTAL)

check("his crops survive", wrote.get("crop"), ON_PORTAL["crop"])
check("the Notion link survives", wrote.get("notion"), ON_PORTAL["notion"])
check("a record key nobody modelled survives", wrote.get("somethingNew"),
      ON_PORTAL["somethingNew"])
check("a picture already on the shelf is kept", "aaa" in (wrote.get("pictures") or {}), True)
check("…and this build's picture is added", "bbb" in (wrote.get("pictures") or {}), True)
check("how many across still survives", wrote["sections"][0]["groups"][0].get("across"),
      {"paper": 3, "web": 2})
check("the words this build carries do go up", wrote.get("words"), ON_PORTAL["words"])

print("\nall good" if ok else "\nSOMETHING WAS LOST")
sys.exit(0 if ok else 1)
