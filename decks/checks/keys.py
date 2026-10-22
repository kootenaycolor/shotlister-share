#!/usr/bin/env python3
"""Does the publisher send pictures by key, never by file name? (Ref 1561)

    python3 decks/checks/keys.py

Builds a throwaway deck folder whose arrangement names its pictures the way
Lens Character's did (`pair-01/a-X.jpg`), runs the publisher's rekey step, and
checks every picture in the result is one of the deck's own keys, that a second
run changes nothing, and that a name no file matches is reported and left alone.
Touches nothing outside a temp folder and sends nothing anywhere.
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from deckcore import Deck, key_for  # noqa: E402
import publish  # noqa: E402

fails = []


def check(ok, what):
    print(("ok    " if ok else "FAIL  ") + what)
    if not ok:
        fails.append(what)


with tempfile.TemporaryDirectory() as t:
    folder = Path(t)
    for pair in ("pair-01", "pair-02"):
        (folder / "img" / pair).mkdir(parents=True)
        for side in ("a", "b"):
            (folder / "img" / pair / f"{side}-X.jpg").write_bytes(b"\xff\xd8\xff\xd9")
    (folder / "sources.json").write_text(json.dumps({"pools": [{
        "id": "bible", "root": str(folder / "img"), "group_glob": "*",
        "file_glob": "*.*", "include": ["pair-01", "pair-02"]}]}))
    (folder / "deck.json").write_text(json.dumps({"version": 1, "sections": []}))
    names = [["pair-01/a-X.jpg", "pair-01/b-X.jpg"], ["pair-02/a-X.jpg", "pair-02/b-X.jpg"]]
    arr = {"version": 1, "sections": [
        {"id": "cover", "on": True},
        {"id": "s1", "on": True, "groups": [
            {"emphasis": "large", "ratio": "1600/1040", "pictures": names[0]},
            {"emphasis": "large", "pictures": names[1] + ["pair-99/nope.jpg"]}]}]}
    (folder / "arrangement.json").write_text(json.dumps(arr))

    deck = Deck(folder)
    changed, lost = publish.normalize_arrangement(deck)
    got = json.loads((folder / "arrangement.json").read_text())
    pics = [p for s in got["sections"] for g in s.get("groups", []) for p in g["pictures"]]
    want = [key_for(str(folder / "img" / n)) for r in names for n in r]
    check(changed == 4, "four file names became keys")
    check(pics[:2] == want[:2] and pics[2:4] == want[2:], "each is the sha1 key of its file, in order")
    check(lost == ["pair-99/nope.jpg"] and pics[-1] == "pair-99/nope.jpg",
          "a name no file matches is reported and left as it was")
    check(got["sections"][1]["groups"][0].get("ratio") == "1600/1040", "the group's crop survives")
    check(list(deck.history.glob("arrangement-*-before-rekey.json")), "the old file went to .history")
    check(publish.normalize_arrangement(deck)[0] == 0, "a second run changes nothing")

sys.exit(1 if fails else 0)
