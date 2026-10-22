"""Merge the cream brand underlay beneath every page of a content PDF.

Usage: python3 merge.py <content.pdf> <out.pdf> [bg.pdf]
"""
import sys
from pypdf import PdfReader, PdfWriter

src, dst = sys.argv[1], sys.argv[2]
bg_path = sys.argv[3] if len(sys.argv) > 3 else "bg.pdf"

content = PdfReader(src)
bg = PdfReader(bg_path)
writer = PdfWriter()

for page in content.pages:
    # Merge the background UNDER the content. Never deep-copy the bg page
    # and merge content onto it; that corrupts fonts on later pages.
    page.merge_page(bg.pages[0], over=False)
    writer.add_page(page)

with open(dst, "wb") as f:
    writer.write(f)

print(dst, "pages:", len(content.pages))
