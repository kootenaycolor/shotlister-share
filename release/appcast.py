#!/usr/bin/env python3
"""Adds one release to the Sparkle feed the other Mac reads.

The feed is a list of every version ever published, newest first. It is added
to rather than replaced on purpose: Sparkle picks the newest entry a given Mac
can actually run, so keeping the older ones is what lets a Mac that has been
shut in a case for six months find its way forward.

Called by release.sh; not meant to be run by hand.
"""

import argparse
import os
import re
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)

EMPTY = """<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="{ns}" version="2.0">
  <channel>
    <title>Shotlister Studio</title>
    <description>Shot lists, storyboards and locations.</description>
    <language>en</language>
  </channel>
</rss>
""".format(ns=SPARKLE)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--feed", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--signature", required=True,
                   help='the whole line sign_update printed')
    p.add_argument("--notes", default="")
    p.add_argument("--minimum-system", default="14.0")
    a = p.parse_args()

    # sign_update prints something like:
    #   sparkle:edSignature="abc…" length="12345"
    # Both halves are needed and neither is optional: Sparkle refuses an
    # enclosure with no signature, and reports a download of the wrong length
    # as a corrupted one.
    sig = re.search(r'edSignature="([^"]+)"', a.signature)
    length = re.search(r'length="(\d+)"', a.signature)
    if not sig or not length:
        raise SystemExit(f"could not read sign_update's output: {a.signature!r}")

    if os.path.exists(a.feed):
        tree = ET.parse(a.feed)
    else:
        tree = ET.ElementTree(ET.fromstring(EMPTY))
    root = tree.getroot()
    channel = root.find("channel")

    # Republishing a version replaces its entry rather than adding a second
    # one, so a release that had to be cut twice does not leave the feed with
    # two answers to the same question.
    for old in channel.findall("item"):
        v = old.find(f"{{{SPARKLE}}}shortVersionString")
        if v is not None and v.text == a.version:
            channel.remove(old)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = a.version
    ET.SubElement(item, "pubDate").text = formatdate(localtime=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = a.build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = a.version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = a.minimum_system
    if a.notes.strip():
        ET.SubElement(item, "description").text = "<ul>" + a.notes + "</ul>"
    ET.SubElement(item, "enclosure", {
        "url": a.url,
        "length": length.group(1),
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": sig.group(1),
    })

    # Newest first.
    first = channel.find("item")
    channel.insert(list(channel).index(first) if first is not None else len(channel), item)

    ET.indent(tree, space="  ")
    tree.write(a.feed, encoding="utf-8", xml_declaration=True)
    print(f"  {a.feed}: {a.version} (build {a.build})")


if __name__ == "__main__":
    main()
