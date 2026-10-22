#!/usr/bin/env python3
"""Round-trip the deck's wording through a markdown file.

Every editable string in the template carries data-t="<key>". Export writes
those to deck-text.md; the build reads that file back and overlays it. Editing
in Notion is fine as long as the "### key" headings survive.
"""

import re

# Elements worth exposing for editing, in the order they appear.
TAGGABLE = [
    (r'<h2>', "h2"),
    (r'<span class="ctx">', "ctx"),
    (r'<p class="lede">', "lede"),
    (r'<p class="tight">', "callout"),
    (r'<p class="small"[^>]*>', "small"),
    (r'<p(?: style="[^"]*")?>', "p"),
    (r'<div class="v">', "v"),
    (r'<div class="k">', "k"),
    (r'<li>', "li"),
    (r'<div class="tag">', "tag"),
    (r'<div class="note">', "note"),
    (r'<div class="cap"[^>]*>', "cap"),
]

OPEN_RE = re.compile(
    r'<(h2|p|li|span|div)((?:\s+[a-zA-Z-]+="[^"]*")*)\s*>'
)


def _close_for(tag):
    return f"</{tag}>"


def tag_section(html, sid):
    """Insert data-t="sid.kind-N" on every taggable element."""
    counts = {}
    out = []
    pos = 0
    for m in OPEN_RE.finditer(html):
        tag, attrs = m.group(1), m.group(2) or ""
        if "data-t=" in attrs:
            continue
        whole = m.group(0)
        kind = None
        for pat, name in TAGGABLE:
            if re.fullmatch(pat, whole):
                kind = name
                break
        if kind is None:
            continue
        counts[kind] = counts.get(kind, 0) + 1
        key = f"{sid}.{kind}{counts[kind]}"
        out.append((m.start(), m.end(), f"<{tag}{attrs} data-t=\"{key}\">"))
    res, last = [], 0
    for s, e, rep in out:
        res.append(html[last:s])
        res.append(rep)
        last = e
    res.append(html[last:])
    return "".join(res)


ELEM_RE = re.compile(
    r'<(h2|p|li|span|div)([^>]*\sdata-t="([^"]+)"[^>]*)>(.*?)</\1>',
    re.S,
)


def extract(html):
    """{key: inner html} for every tagged element."""
    return {m.group(3): m.group(4).strip() for m in ELEM_RE.finditer(html)}


def inject(html, values):
    """Replace inner html of tagged elements from `values`."""
    def rep(m):
        key = m.group(3)
        if key not in values:
            return m.group(0)
        return f"<{m.group(1)}{m.group(2)}>{values[key]}</{m.group(1)}>"
    return ELEM_RE.sub(rep, html)


def html_to_md(s):
    s = re.sub(r"\s*\n\s*", " ", s).strip()
    s = s.replace("<br>", "\n").replace("<br/>", "\n")
    s = re.sub(r"<em>(.*?)</em>", r"*\1*", s)
    s = re.sub(r"<b>(.*?)</b>", r"**\1**", s)
    s = re.sub(r"<span[^>]*>(.*?)</span>", r"\1", s)
    s = re.sub(r"<a [^>]*>(.*?)</a>", r"\1", s)
    s = s.replace("&amp;", "&").replace("&mdash;", "—").replace("&middot;", "·")
    s = s.replace("&eacute;", "é").replace("&nbsp;", " ").replace("&ldquo;", "“")
    s = s.replace("&rdquo;", "”").replace("&gt;", ">").replace("&lt;", "<")
    return re.sub(r"\s{2,}", " ", s).strip()


def md_to_html(s):
    s = s.strip()
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    s = s.replace("ACMECO", "ACME\\CO")
    s = s.replace("&", "&amp;")
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\*(.+?)\*", r"<em>\1</em>", s)
    s = s.replace("\n", "<br>")
    return s


SECTION_LABELS = {
    "cover": "Cover",
    "howiwork": "How I Work",
    "reference": "Reference and Tone",
    "onpaper": "Putting It On Paper",
    "previs": "Previs",
    "look": "Look and Colour",
    "post": "Staying Through Post",
    "contact": "Contact",
}


def to_markdown(sections):
    """sections: ordered [(sid, html)]"""
    lines = [
        "# Deck text",
        "",
        "Edit the text under each `###` heading. Leave the headings themselves alone,",
        "they are how the build finds each piece. Blank lines inside a block are kept.",
        "",
    ]
    for sid, html in sections:
        vals = extract(html)
        if not vals:
            continue
        lines.append(f"## {SECTION_LABELS.get(sid, sid)}")
        lines.append("")
        for k, v in vals.items():
            md = html_to_md(v)
            if not md:
                continue
            lines.append(f"### {k}")
            lines.append("")
            lines.append(md)
            lines.append("")
    return "\n".join(lines)


def parse_markdown(md):
    """Read back {key: html}. Tolerates Notion reformatting."""
    values, key, buf = {}, None, []
    for raw in md.splitlines():
        line = raw.rstrip()
        # Notion auto-links anything that looks like a domain, so a heading
        # can come back as "### [contact.bio](http://contact.bio)1".
        flat = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", line)
        m = re.match(r"^#{3,4}\s+([A-Za-z0-9_.-]+)\s*$", flat)
        if m:
            if key:
                values[key] = md_to_html("\n".join(buf).strip())
            key, buf = m.group(1), []
            continue
        if re.match(r"^#{1,2}\s", line):
            if key:
                values[key] = md_to_html("\n".join(buf).strip())
            key, buf = None, []
            continue
        if key is not None:
            buf.append(line)
    if key:
        values[key] = md_to_html("\n".join(buf).strip())
    return {k: v for k, v in values.items() if v}


def words_markdown(words):
    """A record's words, in the shape `text.md` has always been written in —
    the inverse of `parse_markdown`. The portal holds the words as HTML; the
    file holds them as light markdown, so each goes through `html_to_md` on the
    way in and `md_to_html` on the way back out."""
    out = ["# Deck text", "",
           "Edit the text under each `###` heading. Leave the headings themselves alone,",
           "they are how the build finds each piece. Blank lines inside a block are kept.",
           ""]
    by_section = {}
    for key in words:
        by_section.setdefault(key.split(".")[0], []).append(key)
    for sid, keys in by_section.items():
        out += [f"## {sid.replace('_', ' ').title()}", ""]
        for key in keys:
            said = html_to_md(str(words[key] or ""))
            if said:
                out += [f"### {key}", "", said, ""]
    return "\n".join(out)
