#!/usr/bin/env python3
"""The deck builder, as a tool an AI can use.

His instruction, 2026-09-05: *"it can continue to edit it in deck editor if i so
choose through MCP or whatever channel you think is best"* — the design is never
locked, so after a deck exists an agent has to be able to go on changing it.

## Why this one is local

The portal's MCP is a Cloudflare Worker with a public address, which is why
Notion AI can reach it from Notion's servers. **A deck folder is on his Mac, in
Google Drive**, and has no address at all. So this speaks over stdin and stdout
to whatever is running on the machine — Claude Code, Claude Desktop — and is
reachable from there and nowhere else.

That is a real limit and worth saying plainly: **Notion AI cannot drive this.**
What Notion AI can do is write the film's page on the portal, which is where a
bible's words come from in the first place; `bible.py` then pulls them down.
The two roads meet at the deck folder rather than in the cloud.

## What it will not do

**It does not lay pages out.** Which pictures share a row, and how big they are,
is what Deck Editor is for and what he said he wants to keep doing himself. This
changes words, order, and what is switched on — and prints.

## Adding it

    claude mcp add deck-builder -- /usr/bin/python3 <this file>

or the same command in a client's config. Nothing to install; it uses the
system Python and the tools beside it.
"""

import json
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

PROTOCOL = "2024-11-05"


def registry_deck_name(folder):
    import registry as reg
    return reg.deck_name(folder)


def registry():
    import registry as reg
    return reg.load() if hasattr(reg, "load") else []


def decks():
    """Every deck the launcher knows, straight out of its own list."""
    where = Path.home() / "Library/Application Support/deck-builder/decks.json"
    try:
        return [d for d in json.loads(where.read_text()) if Path(d["path"]).is_dir()]
    except (OSError, ValueError):
        return []


def find(name):
    for d in decks():
        if name.lower() in d["name"].lower() or name == d["path"]:
            return Path(d["path"])
    raise Refused(f"No deck called {name}. Ask for `decks`.")


class Refused(Exception):
    pass


def run(script, folder, *extra):
    got = subprocess.run([sys.executable, str(TOOLS / script), str(folder), *extra],
                         capture_output=True, text=True)
    if got.returncode != 0:
        raise Refused((got.stderr or got.stdout or "it failed").strip()[-600:])
    return (got.stdout or "").strip()


TOOLS_LIST = [
    {"name": "decks",
     "description": "Every deck on this Mac — visual bibles and pitch decks alike — with where each one lives.",
     "inputSchema": {"type": "object", "properties": {}, "required": []}},
    {"name": "deck",
     "description": "One deck's shape: its sections in order, which are switched on, and how many pictures each group holds. Read this before changing anything.",
     "inputSchema": {"type": "object", "properties": {"deck": {"type": "string"}}, "required": ["deck"]}},
    {"name": "copy",
     "description": "Every word in a deck, keyed the way the template asks for them (`dogma.p1`, `lighting.b3`). This is the file Deck Editor edits.",
     "inputSchema": {"type": "object", "properties": {"deck": {"type": "string"}}, "required": ["deck"]}},
    {"name": "set_copy",
     "description": "Change some of a deck's words. Pass only the keys you are changing; everything else is left alone. The PDF and the web page both follow, because they read the same file.",
     "inputSchema": {"type": "object", "properties": {
         "deck": {"type": "string"},
         "words": {"type": "object", "description": "Key to new text, e.g. {\"dogma.p1\": \"We shoot handheld by default.\"}"}},
      "required": ["deck", "words"]}},
    {"name": "set_order",
     "description": "Reorder a deck's sections, or switch some off. Pass the ids in the order you want them; anything left out is switched off rather than deleted.",
     "inputSchema": {"type": "object", "properties": {
         "deck": {"type": "string"},
         "sections": {"type": "array", "items": {"type": "string"}}},
      "required": ["deck", "sections"]}},
    {"name": "design",
     "description": "One of a deck's two designs, as its file. `pdf` is template.html — pages, inch budgets, the cream sheet. `html` is web.html — a flow for a browser, on the portal's own dark ground. `theme` is the colours and the page size the print side uses. They are edited separately on purpose: the same words in two media want different layouts.",
     "inputSchema": {"type": "object", "properties": {
         "deck": {"type": "string"},
         "which": {"type": "string", "description": "`pdf`, `html`, or `theme`."}},
      "required": ["deck", "which"]}},
    {"name": "set_design",
     "description": "Replace one of a deck's two designs. Read it first — this writes the whole file. The other design and all the words are untouched, which is the point: format them separately, and the content they share moves together.",
     "inputSchema": {"type": "object", "properties": {
         "deck": {"type": "string"},
         "which": {"type": "string", "description": "`pdf`, `html`, or `theme`."},
         "content": {"type": "string", "description": "The whole file."}},
      "required": ["deck", "which", "content"]}},
    {"name": "print_pdf",
     "description": "Render the deck to a PDF beside itself.",
     "inputSchema": {"type": "object", "properties": {"deck": {"type": "string"}}, "required": ["deck"]}},
    {"name": "publish_web",
     "description": "Build the deck's web page and put it on the portal, where your-domain.example serves it. The same design as the PDF, laid out for a browser. Any picture in the deck that the portal does not hold yet is put there first, content-addressed, and written into img/portal.json — so a still dropped into img/<section>/ reaches the website as well as the PDF.",
     "inputSchema": {"type": "object", "properties": {"deck": {"type": "string"}}, "required": ["deck"]}},
    {"name": "refresh_from_portal",
     "description": "For a visual bible: pull the film's page down again — its words and pictures — without touching the design or the arrangement. Pictures on that page must already be files the portal holds; if you are writing the page out of Notion, send each picture through the portal's `add_document` with `kind: picture` first, because a Notion picture address expires within the hour and a page that links one is broken by the afternoon.",
     "inputSchema": {"type": "object", "properties": {"deck": {"type": "string"}}, "required": ["deck"]}},
]


def call(name, args):
    if name == "decks":
        found = decks()
        if not found:
            return "No decks on this Mac yet."
        return json.dumps([{"deck": d["name"], "where": d["path"]} for d in found], indent=1)

    folder = find(str(args.get("deck", "")))

    if name == "deck":
        data = json.loads((folder / "deck.json").read_text())
        theme = json.loads((folder / "theme.json").read_text())
        labels = theme.get("section_labels", {})
        groups = {p["slug"]: sum(len(r) for pg in p.get("pages", []) for r in pg)
                  for p in data.get("projects", [])}
        return json.dumps({
            "deck": registry_deck_name(folder),
            "sections": [{"id": s["id"], "called": labels.get(s["id"], s["id"]),
                          "on": s.get("on", True)} for s in data.get("sections", [])],
            "groups": groups,
            "outputs": {"pdf": (folder / "template.html").exists(),
                        "web": (folder / "web.html").exists()},
        }, indent=1)

    if name == "copy":
        from text_io import parse_markdown
        md = (folder / "text.md")
        if not md.exists():
            return "This deck keeps its words in the template, not in text.md."
        import re
        values = parse_markdown(md.read_text())
        # The stored values are HTML; hand back what a person would type.
        plain = {k: re.sub(r"<[^>]+>", "", v).strip() for k, v in values.items()}
        return json.dumps(plain, indent=1, ensure_ascii=False)

    if name == "set_copy":
        words = args.get("words") or {}
        if not isinstance(words, dict) or not words:
            raise Refused("Pass `words` as a map of key to new text.")
        md = folder / "text.md"
        said = md.read_text().splitlines()
        out, key, changed = [], None, 0
        for line in said:
            m = line.strip()
            if m.startswith("### "):
                key = m[4:].strip()
                out.append(line)
                continue
            if key in words:
                continue  # its old body is dropped; the new one is written below
            out.append(line)
        # Rebuild: walk again, writing the new body after each changed key.
        final, key = [], None
        for line in out:
            final.append(line)
            m = line.strip()
            if m.startswith("### "):
                key = m[4:].strip()
                if key in words:
                    final += ["", str(words[key]), ""]
                    changed += 1
        md.write_text("\n".join(final) + "\n")
        missing = [k for k in words if k not in "\n".join(said)]
        return (f"Changed {changed} of {len(words)}."
                + (f" No such key: {', '.join(missing)}." if missing else "")
                + " Print or publish to see it.")

    if name == "set_order":
        wanted = [str(x) for x in (args.get("sections") or [])]
        if not wanted:
            raise Refused("Pass `sections` as the ids in the order you want.")
        path = folder / "deck.json"
        data = json.loads(path.read_text())
        have = {s["id"]: s for s in data.get("sections", [])}
        unknown = [w for w in wanted if w not in have]
        if unknown:
            raise Refused(f"No such section: {', '.join(unknown)}. Ask for `deck`.")
        # **Left out means off, never gone.** An arrangement is his work; a
        # section switched off can be switched back on, a deleted one cannot.
        data["sections"] = ([{**have[w], "on": True} for w in wanted]
                            + [{**s, "on": False} for i, s in have.items() if i not in wanted])
        path.write_text(json.dumps(data, indent=2) + "\n")
        return f"{len(wanted)} sections on, {len(have) - len(wanted)} switched off."

    # **Two designs, one set of words.** His instruction, 2026-09-05: *"the AI
    # should be able to edit and format these separately and also the content of
    # them together"*. So the designs are two files and the copy is one.
    DESIGNS = {"pdf": "template.html", "html": "web.html", "web": "web.html",
               "theme": "theme.json"}

    if name in ("design", "set_design"):
        which = str(args.get("which", "")).lower()
        if which not in DESIGNS:
            raise Refused("Say which: `pdf`, `html`, or `theme`.")
        file = folder / DESIGNS[which]
        if name == "design":
            if not file.exists():
                raise Refused(f"This deck has no {file.name}.")
            return file.read_text()
        said = args.get("content")
        if not isinstance(said, str) or not said.strip():
            raise Refused("Pass the whole file as `content`.")
        if which in ("pdf", "html", "web") and "<!--SECTION:" not in said:
            # **The markers are how a design is assembled at all.** Without one
            # the renderer has nothing to split on and prints an empty deck,
            # which reads as the design being broken rather than incomplete.
            raise Refused("A design needs its <!--SECTION:id--> markers. Read the "
                          "current one first and keep them.")
        if which == "theme":
            try:
                json.loads(said)
            except ValueError as why:
                raise Refused(f"That is not JSON: {why}")
        # The previous one is kept, because a design is work.
        keep = folder / ".history"
        keep.mkdir(exist_ok=True)
        if file.exists():
            (keep / f"{file.stem}-{int(__import__('time').time())}{file.suffix}").write_text(
                file.read_text())
        file.write_text(said)
        return f"Wrote {file.name}. The old one is in .history. Print or publish to see it."

    if name == "print_pdf":
        return run("render.py", folder) or "Printed."
    if name == "publish_web":
        return run("publish.py", folder) or "Published."
    if name == "refresh_from_portal":
        if not (folder / "bible.json").exists():
            raise Refused("That deck is not a film's bible, so there is no page to pull.")
        return run("bible.py", folder) or "Pulled."
    raise Refused(f"No tool called {name}.")


def reply(msg):
    mid = msg.get("id")
    method = msg.get("method", "")
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": PROTOCOL, "capabilities": {"tools": {}},
            "serverInfo": {"name": "deck-builder", "version": "1"}}}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS_LIST}}
    if method == "tools/call":
        p = msg.get("params") or {}
        try:
            said = call(str(p.get("name", "")), p.get("arguments") or {})
        except Refused as why:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32000, "message": str(why)}}
        except Exception as why:  # noqa: BLE001 — the reason goes back, not a stack
            return {"jsonrpc": "2.0", "id": mid,
                    "error": {"code": -32000, "message": f"Could not finish that: {why}"}}
        return {"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": said}]}}
    return {"jsonrpc": "2.0", "id": mid,
            "error": {"code": -32601, "message": f"Unknown method: {method}"}}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("id") is None and "method" in msg:
            continue  # a notification expects no answer
        out = reply(msg)
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
